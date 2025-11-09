#!/usr/bin/env Rscript

#
# StarForth DoE Live Monitor
# Real-time streaming data visualization as experiment progresses
#
# Usage: Rscript live_monitor.R /path/to/experiment_results.csv
#

library(shiny)
library(ggplot2)
library(dplyr)
library(tidyr)

# Get CSV path from command line argument
args <- commandArgs(trailingOnly = TRUE)
csv_path <- if (length(args) > 0) args[1] else "./experiment_results.csv"

if (!file.exists(csv_path)) {
  cat("Error: CSV file not found at", csv_path, "\n")
  quit(status = 1)
}

# ============================================================================
# Data Loading & Utility Functions
# ============================================================================

load_latest_data <- function(csv_path, max_rows = NULL) {
  tryCatch({
    data <- read.csv(csv_path, stringsAsFactors = FALSE)

    if (nrow(data) == 0) return(NULL)

    # Take latest N rows if specified
    if (!is.null(max_rows) && nrow(data) > max_rows) {
      data <- tail(data, max_rows)
    }

    # Convert numeric columns
    numeric_cols <- c("cache_hit_percent", "bucket_hit_percent",
                      "cache_hit_latency_ns", "bucket_search_latency_ns",
                      "context_accuracy_percent", "vm_workload_duration_ns_q48")
    for (col in numeric_cols) {
      if (col %in% names(data)) {
        data[[col]] <- as.numeric(data[[col]])
      }
    }

    data$timestamp <- as.POSIXct(data$timestamp, format = "%Y-%m-%dT%H:%M:%S")
    return(data)
  }, error = function(e) {
    cat("Error loading data:", e$message, "\n")
    return(NULL)
  })
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
    data_refresh()  # Dependency trigger
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
cat("Monitoring:", csv_path, "\n")
cat("Opening Shiny app at: http://127.0.0.1:3838\n")
cat("Press Ctrl+C to exit\n")
cat("=======================================================\n\n")

shinyApp(ui = ui, server = server)
