#!/usr/bin/env Rscript

# StarForth DoE Live Monitor (extended)
# Live visualization for the full Design of Experiments telemetry stream.
# Allows dynamic exploration of every numeric column (~35 metrics per row).

library(shiny)
library(ggplot2)
library(dplyr)
library(tidyr)

# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) {
  if (!is.null(a)) a else b
}

choose_single <- function(current, choices, fallback = NULL) {
  if (!is.null(current) && current %in% choices) {
    return(current)
  }
  if (!is.null(fallback) && fallback %in% choices) {
    return(fallback)
  }
  if (length(choices) > 0) {
    return(choices[1])
  }
  NULL
}

choose_multi <- function(current, choices, fallback = NULL, max_items = NULL) {
  keep <- intersect(current %||% character(0), choices)
  if (length(keep) == 0 && !is.null(fallback)) {
    keep <- intersect(fallback, choices)
  }
  if (length(keep) == 0) {
    keep <- choices
  }
  if (!is.null(max_items) && length(keep) > max_items) {
    keep <- keep[seq_len(max_items)]
  }
  keep
}

fallback_metric <- function(metrics) {
  defaults <- c(
    "cache_hit_percent",
    "bucket_hit_percent",
    "context_accuracy_percent",
    "prefetch_accuracy_percent",
    "vm_workload_duration_ns_q48"
  )
  pick <- intersect(defaults, metrics)
  if (length(pick) > 0) {
    return(pick[1])
  }
  if (length(metrics) > 0) {
    return(metrics[1])
  }
  NULL
}

convert_numeric_columns <- function(df) {
  skip <- c("configuration")
  for (col in names(df)) {
    if (col %in% skip) next
    if (inherits(df[[col]], "POSIXct")) next
    if (is.numeric(df[[col]]) || is.logical(df[[col]])) next

    attempt <- suppressWarnings(as.numeric(df[[col]]))
    if (!all(is.na(attempt))) {
      df[[col]] <- attempt
    }
  }
  df
}

plot_placeholder <- function(message) {
  plot.new()
  text(0.5, 0.5, message, cex = 1.2, col = "gray40")
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

get_script_base <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  script_path <- sub(file_arg, "", cmd_args[grepl(file_arg, cmd_args)])
  if (length(script_path) > 0) {
    return(dirname(normalizePath(script_path[1], winslash = "/", mustWork = TRUE)))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

resolve_csv_path <- function(arg_value, lab_base) {
  append_csv <- function(dir_path) {
    file.path(dir_path, "experiment_results.csv")
  }

  if (!dir.exists(lab_base)) {
    lab_base <- lab_base
  }

  if (!is.null(arg_value)) {
    if (dir.exists(arg_value)) {
      return(normalizePath(append_csv(arg_value), winslash = "/", mustWork = FALSE))
    }

    label_dir <- file.path(lab_base, arg_value)
    if (dir.exists(label_dir)) {
      return(normalizePath(append_csv(label_dir), winslash = "/", mustWork = FALSE))
    }

    if (grepl("\\.csv$", arg_value, ignore.case = TRUE)) {
      return(normalizePath(arg_value, winslash = "/", mustWork = FALSE))
    }

    candidate_dir <- file.path(arg_value)
    return(normalizePath(append_csv(candidate_dir), winslash = "/", mustWork = FALSE))
  }

  if (dir.exists(lab_base)) {
    subdirs <- list.dirs(lab_base, recursive = FALSE, full.names = TRUE)
    subdirs <- subdirs[subdirs != lab_base]
    if (length(subdirs) > 0) {
      latest_dir <- subdirs[which.max(file.info(subdirs)$mtime)]
      return(normalizePath(append_csv(latest_dir), winslash = "/", mustWork = FALSE))
    }
  }

  normalizePath("./experiment_results.csv", winslash = "/", mustWork = FALSE)
}

script_base <- get_script_base()
experiments_base <- file.path(script_base, "experiments")

args <- commandArgs(trailingOnly = TRUE)
input_arg <- if (length(args) > 0) args[1] else NULL
csv_path <- resolve_csv_path(input_arg, experiments_base)
lab_directory <- dirname(csv_path)
csv_exists <- file.exists(csv_path)

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

load_latest_data <- function(csv_path, max_rows = NULL) {
  if (!file.exists(csv_path)) {
    return(NULL)
  }

  data <- tryCatch({
    read.csv(csv_path, stringsAsFactors = FALSE, header = TRUE, strip.white = TRUE)
  }, error = function(e) NULL)

  if (is.null(data) || nrow(data) == 0) {
    return(NULL)
  }

  if (!is.null(max_rows) && nrow(data) > max_rows) {
    data <- tail(data, max_rows)
  }

  if ("timestamp" %in% names(data)) {
    data$timestamp <- suppressWarnings({
      parsed <- as.POSIXct(data$timestamp, format = "%Y-%m-%dT%H:%M:%S")
      if (all(is.na(parsed))) {
        parsed <- as.POSIXct(data$timestamp, format = "%Y-%m-%d %H:%M:%S")
      }
      if (all(is.na(parsed))) {
        parsed <- as.POSIXct(data$timestamp)
      }
      parsed
    })
  } else {
    data$timestamp <- seq(Sys.time(), by = "1 sec", length.out = nrow(data))
  }

  data <- convert_numeric_columns(data)
  data
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- fluidPage(
  titlePanel("StarForth DoE Live Analysis Monitor"),

  fluidRow(
    column(8,
      textOutput("status_text")
    ),
    column(4,
      tags$div(
        style = "text-align: right; color: #666; font-size: 0.85em;",
        tags$span("CSV: "),
        tags$code(csv_path)
      )
    )
  ),
  br(),

  fluidRow(
    column(4,
      checkboxGroupInput(
        inputId = "config_filter",
        label = "Configurations",
        choices = character(0),
        selected = character(0),
        inline = TRUE
      )
    ),
    column(4,
      selectInput(
        inputId = "distribution_metric",
        label = "Distribution metric",
        choices = character(0)
      )
    ),
    column(4,
      selectizeInput(
        inputId = "timeseries_metrics",
        label = "Time-series metrics (max 3)",
        choices = character(0),
        selected = character(0),
        multiple = TRUE,
        options = list(maxItems = 3)
      )
    )
  ),

  tabsetPanel(
    tabPanel(
      title = "Overview",
      fluidRow(
        column(6, plotOutput("boxplot_metric", height = "320px")),
        column(6, plotOutput("density_metric", height = "320px"))
      ),
      br(),
      tableOutput("metric_summary")
    ),

    tabPanel(
      title = "Time Series",
      plotOutput("timeseries_plot", height = "380px"),
      br(),
      tableOutput("latest_snapshot")
    ),

    tabPanel(
      title = "Interactions",
      fluidRow(
        column(4,
          selectInput("scatter_x_metric", "Scatter X-axis", choices = character(0)),
          selectInput("scatter_y_metric", "Scatter Y-axis", choices = character(0))
        ),
        column(8,
          plotOutput("scatter_plot", height = "320px")
        )
      ),
      br(),
      fluidRow(
        column(12,
          selectizeInput(
            inputId = "correlation_metrics",
            label = "Correlation metrics (2-8)",
            choices = character(0),
            selected = character(0),
            multiple = TRUE,
            options = list(maxItems = 8)
          ),
          plotOutput("correlation_heatmap", height = "380px")
        )
      )
    ),

    tabPanel(
      title = "Raw Data",
      tags$p("Latest 20 rows (post-filter). For full context open the CSV."),
      tableOutput("recent_rows")
    )
  ),

  br(),
  hr(),
  fluidRow(
    column(12,
      tags$p("Data refreshes every 3 seconds. Showing the latest 500 observations.",
             style = "color: #6c757d; font-size: 0.9em;")
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {
  data_refresh <- reactiveTimer(3000)
  config_choices <- reactiveVal(NULL)
  metric_choices <- reactiveVal(NULL)

  doe_data <- reactive({
    data_refresh()
    load_latest_data(csv_path, max_rows = 500)
  })

  numeric_metrics <- reactive({
    data <- doe_data()
    if (is.null(data)) {
      return(character(0))
    }
    cols <- names(data)[sapply(data, is.numeric)]
    cols <- setdiff(cols, c("run_number"))
    cols
  })

  observeEvent(doe_data(), {
    data <- doe_data()
    if (is.null(data) || !"configuration" %in% names(data)) {
      updateCheckboxGroupInput(session, "config_filter", choices = character(0), selected = character(0))
      config_choices(NULL)
      return()
    }

    configs <- sort(unique(data$configuration))
    previous <- config_choices()

    if (!is.null(previous) && identical(previous, configs)) {
      return()
    }

    config_choices(configs)
    current <- isolate(input$config_filter)
    selection <- if (is.null(current) || length(current) == 0) configs else intersect(current, configs)
    if (length(selection) == 0) {
      selection <- configs
    }

    updateCheckboxGroupInput(session, "config_filter", choices = configs, selected = selection)
  }, ignoreNULL = FALSE)

  observeEvent(numeric_metrics(), {
    metrics <- numeric_metrics()

    if (length(metrics) == 0) {
      updateSelectInput(session, "distribution_metric", choices = character(0), selected = NULL)
      updateSelectizeInput(session, "timeseries_metrics", choices = character(0), selected = NULL, server = TRUE)
      updateSelectInput(session, "scatter_x_metric", choices = character(0), selected = NULL)
      updateSelectInput(session, "scatter_y_metric", choices = character(0), selected = NULL)
      updateSelectizeInput(session, "correlation_metrics", choices = character(0), selected = NULL, server = TRUE)
      metric_choices(NULL)
      return()
    }

    previous <- metric_choices()
    if (!is.null(previous) && identical(previous, metrics)) {
      return()
    }
    metric_choices(metrics)

    dist_sel <- choose_single(isolate(input$distribution_metric), metrics, fallback_metric(metrics))
    ts_fallback <- metrics[seq_len(min(length(metrics), 3))]
    ts_sel <- choose_multi(isolate(input$timeseries_metrics), metrics, ts_fallback, max_items = 3)
    scatter_x_sel <- choose_single(isolate(input$scatter_x_metric), metrics, fallback_metric(metrics))
    scatter_y_sel <- choose_single(isolate(input$scatter_y_metric), metrics, fallback_metric(rev(metrics)))
    corr_fallback <- metrics[seq_len(min(length(metrics), 6))]
    corr_sel <- choose_multi(isolate(input$correlation_metrics), metrics, corr_fallback, max_items = 8)

    updateSelectInput(session, "distribution_metric", choices = metrics, selected = dist_sel)
    updateSelectizeInput(session, "timeseries_metrics", choices = metrics, selected = ts_sel, server = TRUE)
    updateSelectInput(session, "scatter_x_metric", choices = metrics, selected = scatter_x_sel)
    updateSelectInput(session, "scatter_y_metric", choices = metrics, selected = scatter_y_sel)
    updateSelectizeInput(session, "correlation_metrics", choices = metrics, selected = corr_sel, server = TRUE)
  }, ignoreNULL = FALSE)

  filtered_data <- reactive({
    data <- doe_data()
    if (is.null(data)) {
      return(NULL)
    }
    if (!is.null(input$config_filter) && length(input$config_filter) > 0) {
      data <- data %>% filter(configuration %in% input$config_filter)
    }
    data
  })

  output$status_text <- renderText({
    data <- doe_data()
    if (is.null(data) || nrow(data) == 0) {
      return("Waiting for data...")
    }

    last_time <- data %>% filter(!is.na(timestamp)) %>% summarise(ts = max(timestamp)) %>% pull(ts)
    last_time <- ifelse(is.na(last_time), "n/a", format(last_time, "%Y-%m-%d %H:%M:%S"))

    config_counts <- data %>%
      group_by(configuration) %>%
      summarise(n = n(), .groups = "drop") %>%
      mutate(label = paste0(configuration, ": ", n)) %>%
      pull(label) %>%
      paste(collapse = " | ")

    extra_metrics <- data %>% summarise(
      cache = round(mean(cache_hit_percent, na.rm = TRUE), 2),
      bucket = round(mean(bucket_hit_percent, na.rm = TRUE), 2),
      context = round(mean(context_accuracy_percent, na.rm = TRUE), 2)
    )

    sprintf(
      "Last update: %s | Total rows: %d | Cache %.2f%% | Bucket %.2f%% | Context %.2f%% | %s",
      last_time, nrow(data), extra_metrics$cache, extra_metrics$bucket, extra_metrics$context, config_counts
    )
  })

  output$boxplot_metric <- renderPlot({
    data <- filtered_data()
    metric <- input$distribution_metric
    if (is.null(data) || nrow(data) == 0 || is.null(metric) || !(metric %in% names(data))) {
      return(plot_placeholder("Waiting for numeric data"))
    }

    plot_data <- data %>% mutate(configuration = reorder(configuration, .data[[metric]], FUN = median, na.rm = TRUE))

    ggplot(plot_data, aes_string(x = "configuration", y = metric, fill = "configuration")) +
      geom_boxplot(alpha = 0.75, outlier.alpha = 0.4) +
      geom_jitter(width = 0.15, alpha = 0.25, size = 1.8) +
      labs(title = paste("Distribution by configuration —", metric), x = "Configuration", y = metric) +
      theme_minimal() +
      theme(legend.position = "none", plot.title = element_text(size = 12, face = "bold"))
  })

  output$density_metric <- renderPlot({
    data <- filtered_data()
    metric <- input$distribution_metric
    if (is.null(data) || nrow(data) == 0 || is.null(metric) || !(metric %in% names(data))) {
      return(plot_placeholder("Waiting for numeric data"))
    }

    ggplot(data, aes_string(x = metric, color = "configuration", fill = "configuration")) +
      geom_density(alpha = 0.2) +
      labs(title = paste("Density plot —", metric), x = metric, y = "Density", color = "Config", fill = "Config") +
      theme_minimal() +
      theme(plot.title = element_text(size = 12, face = "bold"))
  })

  output$metric_summary <- renderTable({
    data <- filtered_data()
    metric <- input$distribution_metric
    if (is.null(data) || nrow(data) == 0 || is.null(metric) || !(metric %in% names(data))) {
      return(NULL)
    }

    data %>%
      group_by(configuration) %>%
      summarise(
        rows = n(),
        mean = round(mean(.data[[metric]], na.rm = TRUE), 2),
        sd = round(sd(.data[[metric]], na.rm = TRUE), 2),
        median = round(median(.data[[metric]], na.rm = TRUE), 2),
        min = round(min(.data[[metric]], na.rm = TRUE), 2),
        max = round(max(.data[[metric]], na.rm = TRUE), 2),
        .groups = "drop"
      ) %>%
      rename(Configuration = configuration, Rows = rows, Mean = mean, SD = sd, Median = median, Min = min, Max = max)
  }, striped = TRUE, bordered = TRUE, spacing = "s")

  output$timeseries_plot <- renderPlot({
    data <- filtered_data()
    metrics <- input$timeseries_metrics
    available <- numeric_metrics()

    if (is.null(data) || nrow(data) == 0) {
      return(plot_placeholder("Waiting for data"))
    }

    if (length(metrics) == 0) {
      metrics <- fallback_metric(available)
    }

    metrics <- intersect(metrics, available)
    if (length(metrics) == 0) {
      return(plot_placeholder("Select at least one metric"))
    }

    data_long <- data %>%
      select(timestamp, configuration, all_of(metrics)) %>%
      pivot_longer(cols = all_of(metrics), names_to = "metric", values_to = "value") %>%
      filter(!is.na(value))

    if (nrow(data_long) == 0) {
      return(plot_placeholder("No values for selected metrics"))
    }

    ggplot(data_long, aes(x = timestamp, y = value, color = configuration, linetype = metric)) +
      geom_line(alpha = 0.7, size = 1) +
      geom_point(alpha = 0.5, size = 1.5) +
      labs(title = "Metrics over time", x = "Time", y = "Value", color = "Config", linetype = "Metric") +
      theme_minimal() +
      theme(plot.title = element_text(size = 12, face = "bold"), axis.text.x = element_text(angle = 45, hjust = 1))
  })

  output$latest_snapshot <- renderTable({
    data <- filtered_data()
    metrics <- input$timeseries_metrics
    available <- numeric_metrics()

    if (is.null(data) || nrow(data) == 0) {
      return(NULL)
    }

    if (length(metrics) == 0) {
      metrics <- fallback_metric(available)
    }
    metrics <- intersect(metrics, available)

    data %>%
      group_by(configuration) %>%
      filter(timestamp == max(timestamp, na.rm = TRUE)) %>%
      ungroup() %>%
      arrange(desc(timestamp)) %>%
      mutate(timestamp = format(timestamp, "%Y-%m-%d %H:%M:%S")) %>%
      select(configuration, timestamp, all_of(metrics)) %>%
      rename(Configuration = configuration, Timestamp = timestamp)
  }, bordered = TRUE, spacing = "s")

  output$scatter_plot <- renderPlot({
    data <- filtered_data()
    x_metric <- input$scatter_x_metric
    y_metric <- input$scatter_y_metric

    if (is.null(data) || nrow(data) == 0 || is.null(x_metric) || is.null(y_metric)) {
      return(plot_placeholder("Select two metrics"))
    }

    if (!(x_metric %in% names(data)) || !(y_metric %in% names(data))) {
      return(plot_placeholder("Selected metrics not found"))
    }

    ggplot(data, aes_string(x = x_metric, y = y_metric, color = "configuration")) +
      geom_point(alpha = 0.6, size = 2) +
      geom_smooth(method = "lm", se = FALSE, size = 0.7, linetype = "dashed", alpha = 0.2) +
      labs(title = paste("Scatter:", x_metric, "vs", y_metric), x = x_metric, y = y_metric, color = "Config") +
      theme_minimal() +
      theme(plot.title = element_text(size = 12, face = "bold"))
  })

  output$correlation_heatmap <- renderPlot({
    data <- filtered_data()
    metrics <- input$correlation_metrics

    if (is.null(data) || nrow(data) == 0) {
      return(plot_placeholder("Waiting for data"))
    }
    if (is.null(metrics) || length(metrics) < 2) {
      return(plot_placeholder("Select 2+ metrics"))
    }

    metrics <- intersect(metrics, names(data))
    if (length(metrics) < 2) {
      return(plot_placeholder("Select 2+ numeric metrics"))
    }

    corr <- tryCatch({
      stats::cor(data[, metrics], use = "pairwise.complete.obs")
    }, warning = function(w) NULL, error = function(e) NULL)

    if (is.null(corr)) {
      return(plot_placeholder("Unable to compute correlation"))
    }

    corr_df <- as.data.frame(as.table(round(corr, 3)))
    names(corr_df) <- c("MetricX", "MetricY", "Correlation")

    ggplot(corr_df, aes(x = MetricX, y = MetricY, fill = Correlation)) +
      geom_tile(color = "white") +
      geom_text(aes(label = sprintf("%.2f", Correlation)), size = 3) +
      scale_fill_gradient2(limit = c(-1, 1), low = "#b2182b", mid = "#f7f7f7", high = "#2166ac", midpoint = 0) +
      labs(title = "Metric correlation heatmap", x = NULL, y = NULL) +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1), plot.title = element_text(size = 12, face = "bold"))
  })

  output$recent_rows <- renderTable({
    data <- filtered_data()
    if (is.null(data) || nrow(data) == 0) {
      return(NULL)
    }
    data %>% arrange(desc(timestamp)) %>% head(20)
  }, striped = TRUE, spacing = "xs")
}

# ---------------------------------------------------------------------------
# Banner + App start
# ---------------------------------------------------------------------------

cat("\n")
cat("=======================================================\n")
cat("StarForth DoE Live Monitor\n")
cat("=======================================================\n")
cat("Lab notebook base:", experiments_base, "\n")
cat("Monitoring entry:", lab_directory, "\n")
cat("CSV target:", csv_path, "\n")
if (!csv_exists) {
  cat("(CSV not found yet -- waiting for data to appear)\n")
}
cat("Opening Shiny app at: http://127.0.0.1:3838\n")
cat("Press Ctrl+C to exit\n")
cat("=======================================================\n\n")

shinyApp(ui = ui, server = server)
