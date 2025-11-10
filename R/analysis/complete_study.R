#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(tidyr)
  library(cowplot)
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("Usage: Rscript complete_study.R <csv_file> [output_dir]\\n")
  cat("Example: Rscript complete_study.R ./experiment_results.csv ./analysis_results\\n")
  quit(status = 1)
}

csv_path <- args[1]
output_dir <- if (length(args) > 1) args[2] else "./doe_analysis"

if (!file.exists(csv_path)) {
  cat("Error: CSV file not found at", csv_path, "\\n")
  quit(status = 1)
}

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------

humanize_metric <- function(metric) {
  label <- gsub("_pct$", "_percent", metric)
  label <- gsub("_percent", " %", label, fixed = TRUE)
  label <- gsub("_ns", " (ns)", label, fixed = TRUE)
  label <- gsub("_mhz", " (MHz)", label, fixed = TRUE)
  label <- gsub("_c_q48", " (C)", label, fixed = TRUE)
  label <- gsub("_", " ", label)
  tools::toTitleCase(label)
}

coerce_numeric_columns <- function(df, excludes = c("configuration")) {
  for (name in names(df)) {
    if (name %in% excludes) next
    if (inherits(df[[name]], "POSIXct")) next
    if (is.numeric(df[[name]])) next
    if (is.logical(df[[name]])) {
      df[[name]] <- as.numeric(df[[name]])
      next
    }
    suppressWarnings(num <- as.numeric(df[[name]]))
    if (!all(is.na(num))) {
      df[[name]] <- num
    }
  }
  df
}

identify_numeric_metrics <- function(df) {
  metrics <- names(df)[sapply(df, is.numeric)]
  metrics <- setdiff(metrics, c("run_number"))
  metrics
}

choose_primary_metrics <- function(metrics, limit = 6) {
  priority <- c(
    "cache_hit_percent",
    "bucket_hit_percent",
    "context_accuracy_percent",
    "prefetch_accuracy_percent",
    "vm_workload_duration_ns_q48",
    "cache_hit_latency_ns",
    "bucket_search_latency_ns",
    "cpu_temp_delta_c_q48",
    "cpu_freq_delta_mhz_q48"
  )
  ordered <- unique(c(priority, metrics))
  ordered <- ordered[ordered %in% metrics]
  ordered[seq_len(min(length(ordered), limit))]
}

format_mean_sd <- function(mean_val, sd_val) {
  if (is.na(mean_val)) return("n/a")
  if (is.na(sd_val) || sd_val == 0) {
    return(sprintf("%.2f", mean_val))
  }
  sprintf("%.2f ± %.2f", mean_val, sd_val)
}

safe_aov <- function(formula, data) {
  response <- model.frame(formula, data)[[1]]
  valid <- response[!is.na(response)]
  if (length(valid) < 2 || length(unique(valid)) < 2) {
    return(NULL)
  }
  if (length(unique(data$configuration)) < 2) {
    return(NULL)
  }
  suppressWarnings(tryCatch(aov(formula, data = data), error = function(e) NULL))
}

run_anova_for_metric <- function(metric, data) {
  if (!(metric %in% names(data))) {
    return(NULL)
  }
  formula <- stats::as.formula(sprintf("%s ~ configuration", metric))
  model <- safe_aov(formula, data)
  if (is.null(model)) {
    return(NULL)
  }
  list(
    metric = metric,
    model = model,
    summary = summary(model),
    tukey = tryCatch(TukeyHSD(model), error = function(e) NULL)
  )
}

plot_metric_box <- function(data, metric) {
  ggplot(data, aes(x = configuration, y = .data[[metric]], fill = configuration)) +
    geom_boxplot(alpha = 0.75, outlier.alpha = 0.4) +
    geom_jitter(width = 0.15, alpha = 0.25, size = 1.5) +
    labs(title = humanize_metric(metric), x = "Configuration", y = humanize_metric(metric)) +
    theme_minimal() +
    theme(legend.position = "none", plot.title = element_text(face = "bold"))
}

plot_metric_density <- function(data, metric) {
  ggplot(data, aes(x = .data[[metric]], fill = configuration, color = configuration)) +
    geom_density(alpha = 0.25) +
    labs(title = humanize_metric(metric), x = humanize_metric(metric), y = "Density", fill = "Configuration", color = "Configuration") +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
}

plot_metric_effects <- function(data, metrics) {
  metrics <- intersect(metrics, names(data))
  if (length(metrics) == 0) {
    return(NULL)
  }

  long <- data %>%
    group_by(configuration) %>%
    summarise(across(all_of(metrics), ~mean(.x, na.rm = TRUE)), .groups = "drop") %>%
    pivot_longer(cols = -configuration, names_to = "metric", values_to = "value")

  ggplot(long, aes(x = configuration, y = value, fill = metric)) +
    geom_col(position = "dodge", alpha = 0.85) +
    labs(title = "Mean Metric Effects by Configuration", x = "Configuration", y = "Mean Value", fill = "Metric") +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), axis.text.x = element_text(angle = 45, hjust = 1))
}

plot_correlation_heatmap <- function(data, metrics) {
  metrics <- intersect(metrics, names(data))
  if (length(metrics) < 2) {
    return(NULL)
  }
  corr <- suppressWarnings(tryCatch(stats::cor(data[, metrics], use = "pairwise.complete.obs"), error = function(e) NULL))
  if (is.null(corr)) {
    return(NULL)
  }
  corr_df <- as.data.frame(as.table(round(corr, 3)))
  names(corr_df) <- c("MetricX", "MetricY", "Correlation")

  ggplot(corr_df, aes(x = MetricX, y = MetricY, fill = Correlation)) +
    geom_tile(color = "white") +
    geom_text(aes(label = sprintf("%.2f", Correlation)), size = 3) +
    scale_fill_gradient2(low = "#b2182b", mid = "#f7f7f7", high = "#2166ac", midpoint = 0, limits = c(-1, 1)) +
    labs(title = "Correlation Heatmap", x = NULL, y = NULL) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), plot.title = element_text(face = "bold"))
}

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

load_experiment_data <- function(csv_path) {
  cat("Loading experiment data...\\n")
  data <- as.data.frame(fread(csv_path, integer64 = "numeric"))
  if ("timestamp" %in% names(data)) {
    data$timestamp <- suppressWarnings(as.POSIXct(data$timestamp))
  }
  data <- coerce_numeric_columns(data)
  if ("configuration" %in% names(data)) {
    data$configuration <- as.factor(data$configuration)
  }
  data
}

doe_data <- load_experiment_data(csv_path)
if (!"configuration" %in% names(doe_data)) {
  stop("CSV must include a configuration column")
}

numeric_metrics <- identify_numeric_metrics(doe_data)
if (length(numeric_metrics) == 0) {
  stop("No numeric metrics detected in the dataset")
}

primary_metrics <- choose_primary_metrics(numeric_metrics, limit = 6)
plot_metrics <- primary_metrics

cat("Loaded", nrow(doe_data), "observations across", length(levels(doe_data$configuration)), "configurations\\n")
cat("Tracking", length(numeric_metrics), "numeric metrics\\n\\n")

# ---------------------------------------------------------------------------
# Summaries
# ---------------------------------------------------------------------------

metrics_long <- doe_data %>%
  select(configuration, all_of(numeric_metrics)) %>%
  pivot_longer(cols = all_of(numeric_metrics), names_to = "metric", values_to = "value")

summary_by_config <- metrics_long %>%
  group_by(configuration, metric) %>%
  summarise(
    observations = sum(!is.na(value)),
    mean = mean(value, na.rm = TRUE),
    sd = sd(value, na.rm = TRUE),
    median = median(value, na.rm = TRUE),
    min = min(value, na.rm = TRUE),
    max = max(value, na.rm = TRUE),
    .groups = "drop"
  )

summary_overall <- metrics_long %>%
  group_by(metric) %>%
  summarise(
    observations = sum(!is.na(value)),
    mean = mean(value, na.rm = TRUE),
    sd = sd(value, na.rm = TRUE),
    median = median(value, na.rm = TRUE),
    min = min(value, na.rm = TRUE),
    max = max(value, na.rm = TRUE),
    .groups = "drop"
  )

# ---------------------------------------------------------------------------
# Statistical tests
# ---------------------------------------------------------------------------

cat("Running ANOVA / Tukey across primary metrics...\\n")
anova_results <- lapply(primary_metrics, run_anova_for_metric, data = doe_data)
anova_results <- Filter(Negate(is.null), anova_results)

# ---------------------------------------------------------------------------
# Configuration effects & correlations
# ---------------------------------------------------------------------------

config_effects <- doe_data %>%
  group_by(configuration) %>%
  summarise(across(all_of(primary_metrics), ~mean(.x, na.rm = TRUE)), .groups = "drop")

correlation_metrics <- unique(c(primary_metrics, setdiff(numeric_metrics, primary_metrics)))[seq_len(min(length(numeric_metrics), 12))]
correlation_matrix <- NULL
if (length(correlation_metrics) >= 2) {
  correlation_matrix <- suppressWarnings(tryCatch(
    stats::cor(doe_data[, correlation_metrics], use = "pairwise.complete.obs"),
    error = function(e) NULL
  ))
}

# ---------------------------------------------------------------------------
# Visualizations
# ---------------------------------------------------------------------------

create_plot_grid <- function(plot_func, data, metrics, ncol = 2) {
  metrics <- intersect(metrics, names(data))
  if (length(metrics) == 0) {
    return(NULL)
  }
  plots <- lapply(metrics, function(metric) plot_func(data, metric))
  cowplot::plot_grid(plotlist = plots, ncol = min(ncol, length(plots)))
}

boxplot_path <- file.path(output_dir, "01_boxplots.png")
boxplot_grid <- create_plot_grid(plot_metric_box, doe_data, plot_metrics)
if (!is.null(boxplot_grid)) {
  ggsave(boxplot_path, boxplot_grid, width = 14, height = 8, dpi = 300)
}

density_path <- file.path(output_dir, "02_distributions.png")
density_grid <- create_plot_grid(plot_metric_density, doe_data, plot_metrics)
if (!is.null(density_grid)) {
  ggsave(density_path, density_grid, width = 14, height = 8, dpi = 300)
}

effects_path <- NULL
effects_plot <- plot_metric_effects(doe_data, plot_metrics)
if (!is.null(effects_plot)) {
  effects_path <- file.path(output_dir, "03_effects.png")
  ggsave(effects_path, effects_plot, width = 12, height = 6, dpi = 300)
}

correlation_path <- NULL
correlation_plot <- plot_correlation_heatmap(doe_data, correlation_metrics)
if (!is.null(correlation_plot)) {
  correlation_path <- file.path(output_dir, "04_correlation.png")
  ggsave(correlation_path, correlation_plot, width = 8, height = 8, dpi = 300)
}

# ---------------------------------------------------------------------------
# Persist summaries
# ---------------------------------------------------------------------------

write.csv(summary_by_config, file.path(output_dir, "summary_statistics.csv"), row.names = FALSE)
write.csv(summary_overall, file.path(output_dir, "metric_overview.csv"), row.names = FALSE)
write.csv(config_effects, file.path(output_dir, "configuration_effects.csv"), row.names = FALSE)
if (!is.null(correlation_matrix)) {
  write.csv(correlation_matrix, file.path(output_dir, "correlation_matrix.csv"))
}

# ---------------------------------------------------------------------------
# HTML report assembly
# ---------------------------------------------------------------------------

report_path <- file.path(output_dir, "doe_analysis_report.html")

append_metric_table <- function(html, metric_name) {
  metric_data <- summary_by_config %>% filter(metric == metric_name)
  if (nrow(metric_data) == 0) {
    return(html)
  }
  html <- c(html, sprintf('<h3>%s</h3>', humanize_metric(metric_name)))
  html <- c(html, '<table>')
  html <- c(html, '<tr><th>Configuration</th><th>Observations</th><th>Mean ± SD</th><th>Median</th><th>Min</th><th>Max</th></tr>')
  for (i in seq_len(nrow(metric_data))) {
    row <- metric_data[i, ]
    obs <- ifelse(is.na(row$observations), 'n/a', sprintf('%d', as.integer(round(row$observations))))
    median_val <- ifelse(is.na(row$median), 'n/a', sprintf('%.2f', row$median))
    min_val <- ifelse(is.na(row$min), 'n/a', sprintf('%.2f', row$min))
    max_val <- ifelse(is.na(row$max), 'n/a', sprintf('%.2f', row$max))
    html <- c(html, sprintf(
      '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
      row$configuration,
      obs,
      format_mean_sd(row$mean, row$sd),
      median_val,
      min_val,
      max_val
    ))
  }
  c(html, '</table>')
}

append_anova_section <- function(html, anova_list) {
  if (length(anova_list) == 0) {
    html <- c(html, '<p>No ANOVA results were generated (insufficient variance).</p>')
    return(html)
  }
  for (result in anova_list) {
    html <- c(html, sprintf('<h3>%s</h3>', humanize_metric(result$metric)))
    html <- c(html, '<pre>')
    html <- c(html, paste(capture.output(print(result$summary)), collapse = '\n'))
    html <- c(html, '</pre>')
    if (!is.null(result$tukey)) {
      html <- c(html, '<pre>')
      html <- c(html, paste(capture.output(print(result$tukey)), collapse = '\n'))
      html <- c(html, '</pre>')
    }
  }
  html
}

html_sections <- c(
  '<!DOCTYPE html>',
  '<html>',
  '<head>',
  '<meta charset="utf-8">',
  '<title>StarForth DoE Analysis Report</title>',
  '<style>',
  'body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }',
  '.header { background: #2c3e50; color: white; padding: 20px; border-radius: 6px; }',
  '.section { background: white; padding: 20px; margin: 20px 0; border-radius: 6px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }',
  'table { width: 100%; border-collapse: collapse; margin-top: 10px; }',
  'th, td { padding: 8px 10px; border-bottom: 1px solid #ddd; text-align: left; }',
  'th { background: #3498db; color: white; }',
  'img { max-width: 100%; margin: 10px 0; border: 1px solid #eee; }',
  '</style>',
  '</head>',
  '<body>'
)

html_sections <- c(html_sections,
  '<div class="header">',
  '<h1>StarForth Physics Engine DoE Analysis</h1>',
  sprintf('<p>Generated: %s</p>', format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf('<p>CSV: %s</p>', csv_path),
  '</div>'
)

html_sections <- c(html_sections,
  '<div class="section">',
  '<h2>Executive Summary</h2>',
  sprintf('<p><strong>Total observations:</strong> %d</p>', nrow(doe_data)),
  sprintf('<p><strong>Configurations:</strong> %s</p>', paste(levels(doe_data$configuration), collapse = ', ')),
  sprintf('<p><strong>Tracked metrics:</strong> %d</p>', length(numeric_metrics)),
  '</div>'
)

html_sections <- c(html_sections, '<div class="section"><h2>Metric Highlights</h2>')
for (metric in plot_metrics) {
  html_sections <- append_metric_table(html_sections, metric)
}
html_sections <- c(html_sections, '</div>')

html_sections <- c(html_sections, '<div class="section"><h2>ANOVA & Tukey Tests</h2>')
html_sections <- append_anova_section(html_sections, anova_results)
html_sections <- c(html_sections, '</div>')

html_sections <- c(html_sections, '<div class="section"><h2>Configuration Effects</h2>', '<table>')
html_sections <- c(html_sections, '<tr><th>Configuration</th>')
for (metric in plot_metrics) {
  html_sections <- c(html_sections, sprintf('<th>%s</th>', humanize_metric(metric)))
}
html_sections <- c(html_sections, '</tr>')
for (i in seq_len(nrow(config_effects))) {
  row <- config_effects[i, ]
  html_sections <- c(html_sections, '<tr>')
  html_sections <- c(html_sections, sprintf('<td>%s</td>', row$configuration))
  for (metric in plot_metrics) {
    val <- row[[metric]]
    cell <- ifelse(is.na(val), 'n/a', sprintf('%.2f', val))
    html_sections <- c(html_sections, sprintf('<td>%s</td>', cell))
  }
  html_sections <- c(html_sections, '</tr>')
}
html_sections <- c(html_sections, '</table>', '</div>')

html_sections <- c(html_sections, '<div class="section"><h2>Visualizations</h2>')
if (!is.null(boxplot_grid)) {
  html_sections <- c(html_sections, '<h3>Boxplots</h3>', '<img src="01_boxplots.png" alt="Boxplots">')
}
if (!is.null(density_grid)) {
  html_sections <- c(html_sections, '<h3>Distributions</h3>', '<img src="02_distributions.png" alt="Distributions">')
}
if (!is.null(effects_plot)) {
  html_sections <- c(html_sections, '<h3>Mean Effects</h3>', '<img src="03_effects.png" alt="Effects">')
}
if (!is.null(correlation_path)) {
  html_sections <- c(html_sections, '<h3>Correlation Heatmap</h3>', '<img src="04_correlation.png" alt="Correlation Heatmap">')
}
html_sections <- c(html_sections, '</div>')

html_sections <- c(html_sections, '<div class="section"><h2>Artifacts</h2><ul>')
html_sections <- c(html_sections, '<li>summary_statistics.csv</li>')
html_sections <- c(html_sections, '<li>metric_overview.csv</li>')
html_sections <- c(html_sections, '<li>configuration_effects.csv</li>')
if (!is.null(correlation_matrix)) {
  html_sections <- c(html_sections, '<li>correlation_matrix.csv</li>')
}
if (!is.null(boxplot_grid)) {
  html_sections <- c(html_sections, '<li>01_boxplots.png</li>')
}
if (!is.null(density_grid)) {
  html_sections <- c(html_sections, '<li>02_distributions.png</li>')
}
if (!is.null(effects_plot)) {
  html_sections <- c(html_sections, '<li>03_effects.png</li>')
}
if (!is.null(correlation_plot)) {
  html_sections <- c(html_sections, '<li>04_correlation.png</li>')
}
html_sections <- c(html_sections, '</ul></div>')

html_sections <- c(html_sections, '</body></html>')

writeLines(html_sections, report_path)

# ---------------------------------------------------------------------------
# Console summary
# ---------------------------------------------------------------------------

cat("\\n=======================================================\\n")
cat("Analysis complete\\n")
cat("=======================================================\\n")
cat("Results saved to:", output_dir, "\\n")
cat("Artifacts:\n")
cat("  - summary_statistics.csv\n")
cat("  - metric_overview.csv\n")
cat("  - configuration_effects.csv\n")
if (!is.null(correlation_matrix)) {
  cat("  - correlation_matrix.csv\n")
}
if (!is.null(boxplot_grid)) {
  cat("  - 01_boxplots.png\n")
}
if (!is.null(density_grid)) {
  cat("  - 02_distributions.png\n")
}
if (!is.null(effects_plot)) {
  cat("  - 03_effects.png\n")
}
if (!is.null(correlation_plot)) {
  cat("  - 04_correlation.png\n")
}
cat("  - doe_analysis_report.html\n")
cat("=======================================================\\n\\n")
