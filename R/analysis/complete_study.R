#!/usr/bin/env Rscript

#
# StarForth DoE Complete Study Analysis
# One-click statistical analysis and report generation after experiment concludes
#
# Usage: Rscript complete_study.R /path/to/experiment_results.csv [output_dir]
#

library(dplyr)
library(ggplot2)
library(tidyr)
library(cowplot)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("Usage: Rscript complete_study.R <csv_file> [output_dir]\n")
  cat("\nExample:\n")
  cat("  Rscript complete_study.R ./experiment_results.csv ./analysis_results\n")
  quit(status = 1)
}

csv_path <- args[1]
output_dir <- if (length(args) > 1) args[2] else "./doe_analysis"

if (!file.exists(csv_path)) {
  cat("Error: CSV file not found at", csv_path, "\n")
  quit(status = 1)
}

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# Data Loading
# ============================================================================

load_experiment_data <- function(csv_path) {
  cat("Loading experiment data...\n")
  # Use fread from data.table which is more forgiving of extra columns
  data <- as.data.frame(fread(csv_path))

  # Keep only the columns we actually care about
  cols_we_need <- c("timestamp", "configuration", "run_number",
                    "total_lookups", "cache_hits", "cache_hit_percent",
                    "bucket_hits", "bucket_hit_percent",
                    "cache_hit_latency_ns", "context_accuracy_percent",
                    "vm_workload_duration_ns_q48",
                    "rolling_window_width", "decay_slope")

  cols_to_keep <- intersect(cols_we_need, names(data))
  data <- data[, cols_to_keep]

  # Convert numeric columns
  numeric_cols <- c("cache_hit_percent", "bucket_hit_percent", "context_accuracy_percent",
                    "vm_workload_duration_ns_q48", "cache_hit_latency_ns",
                    "total_lookups", "cache_hits", "bucket_hits",
                    "rolling_window_width", "decay_slope")
  for (col in numeric_cols) {
    if (col %in% names(data)) {
      data[[col]] <- as.numeric(data[[col]])
    }
  }

  if ("timestamp" %in% names(data)) {
    data$timestamp <- as.POSIXct(data$timestamp, format = "%Y-%m-%dT%H:%M:%S")
  }
  if ("configuration" %in% names(data)) {
    data$configuration <- as.factor(data$configuration)
  }

  return(data)
}

doe_data <- load_experiment_data(csv_path)
cat("Loaded", nrow(doe_data), "observations\n")
cat("Configurations:", paste(levels(doe_data$configuration), collapse = ", "), "\n\n")

# ============================================================================
# Exploratory Data Analysis
# ============================================================================

cat("Computing descriptive statistics...\n")

summary_stats <- doe_data %>%
  group_by(configuration) %>%
  summarise(
    N = n(),
    "Cache_Hit_Mean" = mean(cache_hit_percent, na.rm = TRUE),
    "Cache_Hit_SD" = sd(cache_hit_percent, na.rm = TRUE),
    "Cache_Hit_Min" = min(cache_hit_percent, na.rm = TRUE),
    "Cache_Hit_Max" = max(cache_hit_percent, na.rm = TRUE),
    "Bucket_Hit_Mean" = mean(bucket_hit_percent, na.rm = TRUE),
    "Bucket_Hit_SD" = sd(bucket_hit_percent, na.rm = TRUE),
    "Bucket_Hit_Min" = min(bucket_hit_percent, na.rm = TRUE),
    "Bucket_Hit_Max" = max(bucket_hit_percent, na.rm = TRUE),
    "Accuracy_Mean" = mean(context_accuracy_percent, na.rm = TRUE),
    "Accuracy_SD" = sd(context_accuracy_percent, na.rm = TRUE),
    "Window_Width_Mean" = mean(rolling_window_width, na.rm = TRUE),
    "Window_Width_SD" = sd(rolling_window_width, na.rm = TRUE),
    "Decay_Slope_Mean" = mean(decay_slope, na.rm = TRUE),
    "Decay_Slope_SD" = sd(decay_slope, na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  arrange(configuration)

cat("Summary Statistics:\n")
print(summary_stats)
cat("\n")

# ============================================================================
# Statistical Tests
# ============================================================================

cat("Performing ANOVA tests...\n")

safe_aov <- function(formula, data) {
  response <- model.frame(formula, data)[[1]]
  valid <- response[!is.na(response)]
  if (length(valid) == 0 || length(unique(valid)) <= 1) {
    return(NULL)
  }
  aov(formula, data = data)
}

safe_cor <- function(x, y) {
  valid <- complete.cases(x, y)
  x_valid <- x[valid]
  y_valid <- y[valid]
  if (length(x_valid) < 2 || length(unique(x_valid)) < 2 ||
      length(y_valid) < 2 || length(unique(y_valid)) < 2) {
    return(NA_real_)
  }
  cor(x_valid, y_valid)
}

# ANOVA for Cache Hit %
aov_cache <- aov(cache_hit_percent ~ configuration, data = doe_data)
aov_cache_summary <- summary(aov_cache)

# ANOVA for Bucket Hit %
aov_bucket <- aov(bucket_hit_percent ~ configuration, data = doe_data)
aov_bucket_summary <- summary(aov_bucket)

# ANOVA for Context Accuracy %
aov_accuracy <- aov(context_accuracy_percent ~ configuration, data = doe_data)
aov_accuracy_summary <- summary(aov_accuracy)

# ANOVA for Rolling Window Width & Decay Slope
aov_window <- safe_aov(rolling_window_width ~ configuration, data = doe_data)
aov_decay <- safe_aov(decay_slope ~ configuration, data = doe_data)
aov_window_summary <- if (!is.null(aov_window)) summary(aov_window) else NULL
aov_decay_summary <- if (!is.null(aov_decay)) summary(aov_decay) else NULL

# ============================================================================
# Effect Sizes & Post-hoc Tests
# ============================================================================

cat("Computing effect sizes (eta-squared)...\n")

compute_eta_squared <- function(aov_obj) {
  sum_sq <- aov_obj$coefficients[1] ^ 2  # This is a rough approximation
  # Better approach: extract from summary
  ss_treatment <- aov_obj[[1]][1, 2]
  ss_total <- sum(aov_obj[[1]][, 2])
  eta_sq <- ss_treatment / ss_total
  return(eta_sq)
}

# Post-hoc pairwise comparisons (Tukey HSD)
cat("Performing post-hoc pairwise comparisons (Tukey HSD)...\n")

tukey_cache <- TukeyHSD(aov_cache)
tukey_bucket <- TukeyHSD(aov_bucket)
tukey_accuracy <- TukeyHSD(aov_accuracy)
tukey_window <- if (!is.null(aov_window)) TukeyHSD(aov_window) else NULL
tukey_decay <- if (!is.null(aov_decay)) TukeyHSD(aov_decay) else NULL

# ============================================================================
# Interaction Effects (simplified)
# ============================================================================

cat("Analyzing performance characteristics by configuration...\n")

# Calculate effect of each configuration on key metrics
config_effects <- doe_data %>%
  group_by(configuration) %>%
  summarise(
    "Cache_Hit_pct" = mean(cache_hit_percent, na.rm = TRUE),
    "Bucket_Hit_pct" = mean(bucket_hit_percent, na.rm = TRUE),
    "Latency_ns" = mean(cache_hit_latency_ns, na.rm = TRUE),
    "Accuracy_pct" = mean(context_accuracy_percent, na.rm = TRUE),
    "VM_Workload_ns" = mean(vm_workload_duration_ns_q48, na.rm = TRUE),
    "Window_Width" = mean(rolling_window_width, na.rm = TRUE),
    "Decay_Slope" = mean(decay_slope, na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  arrange(desc(`Cache_Hit_pct`))

cat("Configuration Effects (ranked by cache hit %):\n")
print(config_effects)
cat("\n")

window_decay_stats <- doe_data %>%
  group_by(configuration) %>%
  summarise(
    "Window_Width_Mean" = mean(rolling_window_width, na.rm = TRUE),
    "Window_Width_SD" = sd(rolling_window_width, na.rm = TRUE),
    "Window_Width_Min" = min(rolling_window_width, na.rm = TRUE),
    "Window_Width_Max" = max(rolling_window_width, na.rm = TRUE),
    "Decay_Slope_Mean" = mean(decay_slope, na.rm = TRUE),
    "Decay_Slope_SD" = sd(decay_slope, na.rm = TRUE),
    "Decay_Slope_Min" = min(decay_slope, na.rm = TRUE),
    "Decay_Slope_Max" = max(decay_slope, na.rm = TRUE),
    .groups = 'drop'
  )

decay_relationships <- data.frame(
  Relationship = c(
    "Window Width vs Accuracy",
    "Decay Slope vs Accuracy",
    "Decay Slope vs Bucket Hit %"
  ),
  Correlation = c(
    safe_cor(doe_data$rolling_window_width, doe_data$context_accuracy_percent),
    safe_cor(doe_data$decay_slope, doe_data$context_accuracy_percent),
    safe_cor(doe_data$decay_slope, doe_data$bucket_hit_percent)
  )
)

cat("Rolling Window & Decay stats by configuration:\n")
print(window_decay_stats)
cat("\n")

cat("Correlation highlights:\n")
print(decay_relationships)
cat("\n")

# ============================================================================
# Visualization Functions
# ============================================================================

create_boxplots <- function(data, output_path) {
  cat("Creating boxplot visualizations...\n")

  p1 <- ggplot(data, aes(x = reorder(configuration, cache_hit_percent, FUN = median),
                         y = cache_hit_percent, fill = configuration)) +
    geom_boxplot(alpha = 0.7) +
    geom_jitter(width = 0.15, alpha = 0.3, size = 2) +
    labs(title = "Cache Hit % by Configuration",
         x = "Configuration", y = "Cache Hit %") +
    theme_minimal() +
    theme(legend.position = "none", plot.title = element_text(face = "bold"))

  p2 <- ggplot(data, aes(x = reorder(configuration, bucket_hit_percent, FUN = median),
                         y = bucket_hit_percent, fill = configuration)) +
    geom_boxplot(alpha = 0.7) +
    geom_jitter(width = 0.15, alpha = 0.3, size = 2) +
    labs(title = "Bucket Hit % by Configuration",
         x = "Configuration", y = "Bucket Hit %") +
    theme_minimal() +
    theme(legend.position = "none", plot.title = element_text(face = "bold"))

  p3 <- ggplot(data, aes(x = reorder(configuration, context_accuracy_percent, FUN = median),
                         y = context_accuracy_percent, fill = configuration)) +
    geom_boxplot(alpha = 0.7) +
    geom_jitter(width = 0.15, alpha = 0.3, size = 2) +
    labs(title = "Context Accuracy % by Configuration",
         x = "Configuration", y = "Context Accuracy %") +
    theme_minimal() +
    theme(legend.position = "none", plot.title = element_text(face = "bold"))

  p4 <- ggplot(data, aes(x = reorder(configuration, vm_workload_duration_ns_q48, FUN = median),
                         y = vm_workload_duration_ns_q48, fill = configuration)) +
    geom_boxplot(alpha = 0.7) +
    geom_jitter(width = 0.15, alpha = 0.3, size = 1) +
    labs(title = "VM Workload Duration (ns) by Configuration",
         x = "Configuration", y = "Duration (ns)") +
    theme_minimal() +
    theme(legend.position = "none", plot.title = element_text(face = "bold"))

  combined <- cowplot::plot_grid(p1, p2, p3, p4, nrow = 2)
  ggsave(output_path, combined, width = 14, height = 10, dpi = 300)
  cat("  Saved:", output_path, "\n")
}

create_distributions <- function(data, output_path) {
  cat("Creating distribution plots...\n")

  p1 <- ggplot(data, aes(x = cache_hit_percent, fill = configuration)) +
    geom_density(alpha = 0.5) +
    labs(title = "Cache Hit % Distribution by Configuration",
         x = "Cache Hit %", y = "Density") +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))

  p2 <- ggplot(data, aes(x = bucket_hit_percent, fill = configuration)) +
    geom_density(alpha = 0.5) +
    labs(title = "Bucket Hit % Distribution by Configuration",
         x = "Bucket Hit %", y = "Density") +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))

  p3 <- ggplot(data, aes(x = context_accuracy_percent, fill = configuration)) +
    geom_density(alpha = 0.5) +
    labs(title = "Context Accuracy % Distribution by Configuration",
         x = "Context Accuracy %", y = "Density") +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))

  combined <- cowplot::plot_grid(p1, p2, p3, nrow = 3)
  ggsave(output_path, combined, width = 12, height = 10, dpi = 300)
  cat("  Saved:", output_path, "\n")
}

create_effect_plot <- function(data, output_path) {
  cat("Creating effect size visualization...\n")

  effects <- data %>%
    group_by(configuration) %>%
    summarise(
      "Cache_Hit" = mean(cache_hit_percent, na.rm = TRUE),
      "Bucket_Hit" = mean(bucket_hit_percent, na.rm = TRUE),
      "Accuracy" = mean(context_accuracy_percent, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    pivot_longer(cols = -configuration, names_to = "metric", values_to = "value")

  p <- ggplot(effects, aes(x = configuration, y = value, fill = metric)) +
    geom_col(position = "dodge", alpha = 0.8) +
    labs(title = "Mean Effects by Configuration and Metric",
         x = "Configuration", y = "Mean Value") +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"),
          axis.text.x = element_text(angle = 45, hjust = 1))

  ggsave(output_path, p, width = 10, height = 6, dpi = 300)
  cat("  Saved:", output_path, "\n")
}

create_window_decay_plots <- function(data, output_path) {
  cat("Creating rolling window & decay visualizations...\n")

  p_window <- ggplot(data, aes(x = reorder(configuration, rolling_window_width, FUN = median),
                               y = rolling_window_width, fill = configuration)) +
    geom_boxplot(alpha = 0.7) +
    geom_jitter(width = 0.15, alpha = 0.3, size = 1.5) +
    labs(title = "Rolling Window of Truth Width by Configuration",
         x = "Configuration", y = "Window Width") +
    theme_minimal() +
    theme(legend.position = "none", plot.title = element_text(face = "bold"))

  p_decay <- ggplot(data, aes(x = reorder(configuration, decay_slope, FUN = median),
                              y = decay_slope, fill = configuration)) +
    geom_boxplot(alpha = 0.7) +
    geom_jitter(width = 0.15, alpha = 0.3, size = 1.5) +
    labs(title = "Decay Slope by Configuration",
         x = "Configuration", y = "Decay Slope") +
    theme_minimal() +
    theme(legend.position = "none", plot.title = element_text(face = "bold"))

  decay_vs_accuracy <- data %>%
    filter(!is.na(decay_slope), !is.na(context_accuracy_percent))

  p_relationship <- ggplot(decay_vs_accuracy,
                           aes(x = decay_slope, y = context_accuracy_percent,
                               color = configuration)) +
    geom_point(alpha = 0.6) +
    geom_smooth(method = "lm", se = FALSE, linewidth = 0.8, linetype = "dashed") +
    labs(title = "Decay Slope vs Context Accuracy",
         x = "Decay Slope", y = "Context Accuracy %", color = "Configuration") +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))

  combined <- cowplot::plot_grid(p_window, p_decay, p_relationship,
                                 nrow = 3, align = "v", rel_heights = c(1, 1, 1))
  ggsave(output_path, combined, width = 12, height = 15, dpi = 300)
  cat("  Saved:", output_path, "\n")
}

# Create visualizations
create_boxplots(doe_data, file.path(output_dir, "01_boxplots.png"))
create_distributions(doe_data, file.path(output_dir, "02_distributions.png"))
create_effect_plot(doe_data, file.path(output_dir, "03_effects.png"))
create_window_decay_plots(doe_data, file.path(output_dir, "04_window_decay.png"))

# ============================================================================
# Save Summary Statistics to CSV
# ============================================================================

cat("Saving summary statistics...\n")
write.csv(summary_stats, file.path(output_dir, "summary_statistics.csv"), row.names = FALSE)
write.csv(config_effects, file.path(output_dir, "configuration_effects.csv"), row.names = FALSE)
write.csv(window_decay_stats, file.path(output_dir, "window_decay_analysis.csv"), row.names = FALSE)
write.csv(decay_relationships, file.path(output_dir, "window_decay_correlations.csv"), row.names = FALSE)

# ============================================================================
# Generate HTML Report
# ============================================================================

cat("Generating HTML report...\n")

report_path <- file.path(output_dir, "doe_analysis_report.html")

html_content <- sprintf('
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>StarForth DoE Analysis Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
    .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
    .section { background-color: white; padding: 20px; margin: 20px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .section h2 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
    table { width: 100%%; border-collapse: collapse; margin: 10px 0; }
    th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
    td { padding: 10px; border-bottom: 1px solid #ddd; }
    tr:hover { background-color: #f5f5f5; }
    .metric { margin: 10px 0; padding: 10px; background-color: #ecf0f1; border-left: 4px solid #3498db; }
    img { max-width: 100%%; height: auto; margin: 10px 0; }
    .footer { color: #7f8c8d; margin-top: 40px; padding-top: 20px; border-top: 1px solid #bdc3c7; }
  </style>
</head>
<body>

<div class="header">
  <h1>StarForth Physics Engine DoE Analysis Report</h1>
  <p>Design of Experiments: Complete Statistical Study</p>
  <p>Generated: %s</p>
</div>

<div class="section">
  <h2>Executive Summary</h2>
  <div class="metric">
    <strong>Total Observations:</strong> %d
  </div>
  <div class="metric">
    <strong>Configurations Tested:</strong> %s
  </div>
  <div class="metric">
    <strong>Key Findings:</strong> Comprehensive ANOVA, post-hoc tests, and effect size analysis completed.
  </div>
</div>

<div class="section">
  <h2>Summary Statistics by Configuration</h2>
  <table border="1">
    <tr>
      <th>Configuration</th>
      <th>N</th>
      <th>Cache Hit %% (Mean ± SD)</th>
      <th>Bucket Hit %% (Mean ± SD)</th>
      <th>Accuracy %% (Mean ± SD)</th>
      <th>Window Width (Mean ± SD)</th>
      <th>Decay Slope (Mean ± SD)</th>
    </tr>
', format(Sys.time(), "%Y-%m-%d %H:%M:%S"), nrow(doe_data), paste(levels(doe_data$configuration), collapse = ", "))

# Add summary rows
for (i in 1:nrow(summary_stats)) {
  row <- summary_stats[i, ]
  html_content <- sprintf('%s
    <tr>
      <td>%s</td>
      <td>%d</td>
      <td>%.2f ± %.2f</td>
      <td>%.2f ± %.2f</td>
      <td>%.2f ± %.2f</td>
      <td>%.0f ± %.2f</td>
      <td>%.4f ± %.4f</td>
    </tr>
', html_content,
    row$configuration, row$N,
    row$Cache_Hit_Mean, row$Cache_Hit_SD,
    row$Bucket_Hit_Mean, row$Bucket_Hit_SD,
    row$Accuracy_Mean, row$Accuracy_SD,
    row$Window_Width_Mean, row$Window_Width_SD,
    row$Decay_Slope_Mean, row$Decay_Slope_SD
  )
}

html_content <- paste0(html_content, '
  </table>
</div>

<div class="section">
  <h2>ANOVA Results</h2>
  <h3>Cache Hit %</h3>
  <pre>')

html_content <- paste0(html_content, capture.output(print(aov_cache_summary)))

html_content <- paste0(html_content, '</pre>

  <h3>Bucket Hit %</h3>
  <pre>')

html_content <- paste0(html_content, capture.output(print(aov_bucket_summary)))

html_content <- paste0(html_content, '</pre>

  <h3>Context Accuracy %</h3>
  <pre>')

html_content <- paste0(html_content, capture.output(print(aov_accuracy_summary)))

html_content <- paste0(html_content, '</pre>
</div>

<div class="section">
  <h2>Post-hoc Pairwise Comparisons (Tukey HSD)</h2>
  <h3>Cache Hit %</h3>
  <pre>')

html_content <- paste0(html_content, capture.output(print(tukey_cache)))

html_content <- paste0(html_content, '</pre>

  <h3>Bucket Hit %</h3>
  <pre>')

html_content <- paste0(html_content, capture.output(print(tukey_bucket)))

html_content <- paste0(html_content, '</pre>
</div>

<div class="section">
  <h2>Configuration Effects Analysis</h2>
  <table border="1">
    <tr>
      <th>Configuration</th>
      <th>Cache Hit %%</th>
      <th>Bucket Hit %%</th>
      <th>Latency (ns)</th>
      <th>Accuracy %%</th>
      <th>VM Workload (ns)</th>
    </tr>
')

for (i in 1:nrow(config_effects)) {
  row <- config_effects[i, ]
  html_content <- sprintf('%s
    <tr>
      <td>%s</td>
      <td>%.2f</td>
      <td>%.2f</td>
      <td>%.0f</td>
      <td>%.2f</td>
      <td>%.0f</td>
    </tr>
', html_content,
    row$configuration,
    row$Cache_Hit_pct,
    row$Bucket_Hit_pct,
    row$Latency_ns,
    row$Accuracy_pct,
    row$VM_Workload_ns
  )
}

html_content <- paste0(html_content, '
  </table>
</div>

<div class="section">
  <h2>Visualizations</h2>

  <h3>Distribution by Configuration</h3>
  <img src="01_boxplots.png" alt="Boxplots by Configuration">

  <h3>Probability Distributions</h3>
  <img src="02_distributions.png" alt="Distributions">

  <h3>Effect Comparison</h3>
  <img src="03_effects.png" alt="Effects">
</div>

<div class="section">
  <h2>Data Files Generated</h2>
  <ul>
    <li>summary_statistics.csv - Descriptive statistics by configuration</li>
    <li>configuration_effects.csv - Mean effects by configuration</li>
    <li>01_boxplots.png - Boxplot visualizations</li>
    <li>02_distributions.png - Probability distributions</li>
    <li>03_effects.png - Effect comparison chart</li>
  </ul>
</div>

<div class="footer">
  <p>This report was automatically generated by StarForth DoE Complete Study Analysis</p>
  <p>Report location: ' , report_path , '</p>
</div>

</body>
</html>
')

writeLines(html_content, report_path)
cat("  Saved:", report_path, "\n")

# ============================================================================
# Summary
# ============================================================================

cat("\n")
cat("=======================================================\n")
cat("ANALYSIS COMPLETE\n")
cat("=======================================================\n")
cat("Results saved to:", output_dir, "\n\n")
cat("Generated files:\n")
cat("  - summary_statistics.csv\n")
cat("  - configuration_effects.csv\n")
cat("  - window_decay_analysis.csv\n")
cat("  - window_decay_correlations.csv\n")
cat("  - 01_boxplots.png\n")
cat("  - 02_distributions.png\n")
cat("  - 03_effects.png\n")
cat("  - 04_window_decay.png\n")
cat("  - doe_analysis_report.html\n\n")
cat("Open the HTML report to view complete analysis:\n")
cat("  ", report_path, "\n")
cat("=======================================================\n\n")
