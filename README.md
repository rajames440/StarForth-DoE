# StarForth DoE Analysis Suite

Two-part analysis system for Design of Experiments data: **Live Monitoring** during experiment execution and **Complete Statistical Study** after experiment concludes.

---

## 1. LIVE MONITOR - Real-time Streaming Data Visualization

Monitor your experiment as data flows in from the physics engine. Updates every 3 seconds.

### Requirements

```r
install.packages("shiny")
install.packages("ggplot2")
install.packages("dplyr")
install.packages("tidyr")

# Check if they're installed
packages <- c("shiny", "ggplot2", "dplyr", "tidyr")
missing <- packages[!sapply(packages, function(pkg) require(pkg, character.only = TRUE, quietly = TRUE))]
if (length(missing) > 0) install.packages(missing)
```

### Usage

```bash
# While experiment is running
Rscript live_monitor.R /path/to/experiment_results.csv
```

**Example:**
```bash
./scripts/run_doe.sh --exp-iterations 2 ./DOE_results &
Rscript live_monitor.R ./DOE_results/experiment_results.csv
```

### What You See

- **Status Line**: Real-time counts by configuration
- **Cache Hit % Boxplot**: Distribution of cache performance across configs
- **Bucket Hit % Boxplot**: Distribution of bucket performance across configs
- **Time Series Plot**: Metrics over time with trend lines
- **Summary Statistics Table**: Mean ± SD for each configuration

The app auto-refreshes every 3 seconds showing the latest 500 observations.

---

## 2. COMPLETE STUDY - Full Statistical Analysis & Report

After your experiment finishes, run this for comprehensive statistical analysis with publication-quality visualizations.

### Requirements

```r
# These are typically pre-installed, but just in case:
install.packages("dplyr")
install.packages("ggplot2")
install.packages("tidyr")
install.packages("cowplot")
install.packages("data.table")

# Check if they're installed
packages <- c("dplyr", "ggplot2", "tidyr", "cowplot", "data.table")
missing <- packages[!sapply(packages, function(pkg) require(pkg, character.only = TRUE, quietly = TRUE))]
if (length(missing) > 0) install.packages(missing)
```

### Usage

```bash
# After experiment completes
Rscript complete_study.R <csv_file> [output_directory]
```

**Examples:**

```bash
# Basic usage
Rscript complete_study.R ./DOE_results/experiment_results.csv

# Specify output directory
Rscript complete_study.R ./DOE_results/experiment_results.csv ./analysis_results
```

### Generated Output

Creates an analysis directory with:

```
analysis_results/
├── doe_analysis_report.html       ← Main report (open in browser)
├── summary_statistics.csv         ← Descriptive stats by config
├── configuration_effects.csv      ← Mean effects comparison
├── 01_boxplots.png               ← 4-panel boxplot visualization
├── 02_distributions.png          ← Probability distributions
└── 03_effects.png                ← Effect size comparison chart
```

### Analysis Included

✓ **Descriptive Statistics**
  - N, Mean, SD, Min, Max per configuration
  - Cache Hit %, Bucket Hit %, Context Accuracy %

✓ **ANOVA Tests**
  - Test for significant differences between configurations
  - Separate tests for: cache hit %, bucket hit %, context accuracy %

✓ **Post-hoc Comparisons**
  - Tukey HSD pairwise tests
  - Identify which config pairs differ significantly

✓ **Effect Sizes**
  - Configuration effects on all key metrics
  - VM workload analysis
  - Latency characteristics

✓ **Visualizations**
  - Boxplots with raw data overlaid
  - Probability density distributions
  - Effect size bar charts

---

## Workflow Example

### Full Pipeline

```bash
#!/bin/bash

# 1. Start monitoring in background
Rscript live_monitor.R ./DOE_results/experiment_results.csv &
MONITOR_PID=$!

# 2. Run experiment
./scripts/run_nested_doe.sh --exp-iterations 2 ./DOE_results

# 3. Kill monitor
kill $MONITOR_PID

# 4. Generate complete analysis
Rscript complete_study.R ./DOE_results/experiment_results.csv ./doe_analysis

# 5. View results
open ./doe_analysis/doe_analysis_report.html  # macOS
# or
xdg-open ./doe_analysis/doe_analysis_report.html  # Linux
```

---

## CSV Format Expected

Both scripts expect the standard output from `run_doe.sh` or `run_nested_doe.sh`:

```
timestamp,configuration,run_number,total_lookups,cache_hits,cache_hit_percent,...
2025-11-09T05:55:28,A_B_CACHE,9,3865,0,0.00,...
...
```

**Key Columns Used:**
- `timestamp` - Experiment timestamp
- `configuration` - Build config (A_BASELINE, A_B_CACHE, A_C_FULL, A_B_C_FULL)
- `cache_hit_percent` - Cache performance metric
- `bucket_hit_percent` - Bucket performance metric
- `context_accuracy_percent` - Prediction accuracy
- `vm_workload_duration_ns_q48` - Workload duration
- `cache_hit_latency_ns` - Cache latency

---

## Troubleshooting

### "Error: CSV file not found"
Make sure the CSV path is correct and the file exists.

### "No data yet" in Live Monitor
The CSV might be empty. Check that your experiment has started writing data.

### Shiny app won't open
Port 3838 may be in use. Manually open http://127.0.0.1:3838 in your browser.

### HTML report not displaying images
Make sure you open the HTML file from its directory (not moving it elsewhere first).

### Missing packages
Install missing R packages:
```r
install.packages(c("shiny", "ggplot2", "dplyr", "tidyr", "gridExtra"))
```

---

## Making Scripts Executable

```bash
chmod +x /home/rajames/CLionProjects/StarForth-DoE/live_monitor.R
chmod +x /home/rajames/CLionProjects/StarForth-DoE/complete_study.R
```

Then you can run them as:
```bash
./live_monitor.R /path/to/csv
./complete_study.R /path/to/csv ./output_dir
```

---

## Notes

- **Live Monitor** shows rolling window of latest ~500 observations to avoid memory bloat
- **Complete Study** processes entire dataset (useful for final analysis)
- Both are non-destructive (read-only operations on CSV)
- Reports generated in HTML for easy sharing
- All statistics use `na.rm = TRUE` to handle any missing values gracefully
