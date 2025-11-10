#!/usr/bin/env Rscript

#
# StarForth DoE Live Monitor
# Real-time streaming data visualization as experiment progresses
#
# Usage:
#   Rscript live_monitor.R DOE_01          # looks under ./experiments/DOE_01/
#   Rscript live_monitor.R experiments/DOE_01
#   Rscript live_monitor.R /full/path/to/experiment_results.csv
#   Rscript live_monitor.R                 # defaults to most recent lab book entry
#

library(shiny)
library(ggplot2)
library(dplyr)
library(tidyr)

# Determine repository base relative to script location so we can always
# resolve ./experiments/<label>/experiment_results.csv regardless of cwd.
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

# Get CSV path from command line argument or resolve via lab book directory
args <- commandArgs(trailingOnly = TRUE)
input_arg <- if (length(args) > 0) args[1] else NULL
csv_path <- resolve_csv_path(input_arg, experiments_base)
lab_directory <- dirname(csv_path)
csv_exists <- file.exists(csv_path)

# ============================================================================
# Data Loading & Utility Functions
# ============================================================================

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

  # Take latest N rows if specified
  if (!is.null(max_rows) && nrow(data) > max_rows) {
    data <- tail(data, max_rows)
  }

  # Convert numeric columns with suppressWarnings
  numeric_cols <- c("cache_hit_percent", "bucket_hit_percent",
                    "cache_hit_latency_ns", "bucket_search_latency_ns",
                    "context_accuracy_percent", "vm_workload_duration_ns_q48")
  for (col in numeric_cols) {
    if (col %in% names(data)) {
      data[[col]] <- suppressWarnings(as.numeric(as.character(data[[col]])))
    }
  }

  # Handle timestamp - try multiple approaches
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

  return(data)
}

# ============================================================================
# UI Definition
# ============================================================================

ui <- fluidPage(
  titlePanel("StarForth DoE Live Analysis Monitor"),

  fluidRow(
    column(12,
      textOutput("status_text"),
      br()
    )
  ),

  # Main metrics row
  fluidRow(
    column(6, plotOutput("boxplot_cache")),
    column(6, plotOutput("boxplot_bucket"))
  ),

  # Time series row
  fluidRow(
    column(12, plotOutput("timeseries_plot"))
  ),

  # Statistics table row
  fluidRow(
    column(12, tableOutput("summary_stats"))
  ),

  # Footer
  fluidRow(
    column(12,
      hr(),
      p("Data updates every 3 seconds. Showing latest 500 observations.", style = "color: gray;")
    )
  )
)

# ============================================================================
# Server Definition
# ============================================================================

server <- function(input, output, session) {

  # Auto-refresh every 3 seconds
  data_refresh <- reactiveTimer(3000)

  # Reactive data source
  doe_data <- reactive({
    data_refresh()
    load_latest_data(csv_path, max_rows = 500)
  })

  # Status text
  output$status_text <- renderText({
    data <- doe_data()
    if (is.null(data) || nrow(data) == 0) {
      "Waiting for data..."
    } else {
      last_time <- format(max(data$timestamp), "%Y-%m-%d %H:%M:%S")
      config_counts <- data %>%
        group_by(configuration) %>%
        summarise(n = n(), .groups = 'drop') %>%
        mutate(label = paste0(configuration, ": ", n)) %>%
        pull(label) %>%
        paste(collapse = " | ")

      sprintf("Last update: %s | Total observations: %d | %s",
              last_time, nrow(data), config_counts)
    }
  })

  # Boxplot: Cache Hit % by Configuration
  output$boxplot_cache <- renderPlot({
    data <- doe_data()
    if (is.null(data) || nrow(data) == 0) {
      plot.new()
      text(0.5, 0.5, "No data yet", cex = 2, col = "gray")
      return()
    }

    ggplot(data, aes(x = reorder(configuration, cache_hit_percent, FUN = median),
                     y = cache_hit_percent, fill = configuration)) +
      geom_boxplot(alpha = 0.7, outlier.alpha = 0.5) +
      geom_jitter(width = 0.15, alpha = 0.3, size = 2) +
      labs(title = "Cache Hit % Distribution by Configuration",
           x = "Configuration", y = "Cache Hit %") +
      theme_minimal() +
      theme(legend.position = "none",
            plot.title = element_text(face = "bold", size = 12))
  })

  # Boxplot: Bucket Hit % by Configuration
  output$boxplot_bucket <- renderPlot({
    data <- doe_data()
    if (is.null(data) || nrow(data) == 0) {
      plot.new()
      text(0.5, 0.5, "No data yet", cex = 2, col = "gray")
      return()
    }

    ggplot(data, aes(x = reorder(configuration, bucket_hit_percent, FUN = median),
                     y = bucket_hit_percent, fill = configuration)) +
      geom_boxplot(alpha = 0.7, outlier.alpha = 0.5) +
      geom_jitter(width = 0.15, alpha = 0.3, size = 2) +
      labs(title = "Bucket Hit % Distribution by Configuration",
           x = "Configuration", y = "Bucket Hit %") +
      theme_minimal() +
      theme(legend.position = "none",
            plot.title = element_text(face = "bold", size = 12))
  })

  # Time series: Metrics over time
  output$timeseries_plot <- renderPlot({
    data <- doe_data()
    if (is.null(data) || nrow(data) == 0) {
      plot.new()
      text(0.5, 0.5, "No data yet", cex = 2, col = "gray")
      return()
    }

    # Prepare data for plotting
    data_long <- data %>%
      select(timestamp, configuration, cache_hit_percent, bucket_hit_percent) %>%
      pivot_longer(cols = c(cache_hit_percent, bucket_hit_percent),
                   names_to = "metric", values_to = "value") %>%
      mutate(metric = ifelse(metric == "cache_hit_percent", "Cache Hit %", "Bucket Hit %"))

    ggplot(data_long, aes(x = timestamp, y = value, color = configuration, linetype = metric)) +
      geom_line(alpha = 0.6, size = 1) +
      geom_point(size = 2, alpha = 0.5) +
      labs(title = "Metrics Over Time",
           x = "Time", y = "Percentage", color = "Configuration", linetype = "Metric") +
      theme_minimal() +
      theme(plot.title = element_text(face = "bold", size = 12),
            axis.text.x = element_text(angle = 45, hjust = 1))
  })

  # Summary statistics table
  output$summary_stats <- renderTable({
    data <- doe_data()
    if (is.null(data) || nrow(data) == 0) {
      return(NULL)
    }

    data %>%
      group_by(configuration) %>%
      summarise(
        N = n(),
        "Cache Hit % (Mean)" = round(mean(cache_hit_percent, na.rm = TRUE), 2),
        "Cache Hit % (SD)" = round(sd(cache_hit_percent, na.rm = TRUE), 2),
        "Bucket Hit % (Mean)" = round(mean(bucket_hit_percent, na.rm = TRUE), 2),
        "Bucket Hit % (SD)" = round(sd(bucket_hit_percent, na.rm = TRUE), 2),
        .groups = 'drop'
      ) %>%
      rename("Configuration" = configuration)
  }, bordered = TRUE, spacing = "s")
}

# ============================================================================
# Run Application
# ============================================================================

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
