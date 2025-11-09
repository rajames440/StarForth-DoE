# StarForth DoE Analysis Suite

Two-part analysis system for Design of Experiments data: **Live Monitoring** during experiment execution and **Complete Statistical Study** after experiment concludes.

---

## Quick Start (for R beginners)

1. Install R (https://cran.r-project.org) and, optionally, RStudio (https://posit.co/download/rstudio-desktop/).
2. Open a terminal in the project root directory.
3. Install required packages (one-time):
   ```bash
   Rscript R/analysis/install_packages.R
   ```
4. Run the live monitor while an experiment is running:
   ```bash
   Rscript R/analysis/live_monitor.R experiments/EXP_00/experiment_results.csv
   ```
5. After the experiment finishes, generate the complete analysis:
   ```bash
   Rscript R/analysis/complete_study.R experiments/EXP_00/experiment_results.csv outputs/EXP_00
   ```
6. Open the report HTML file printed at the end of the script.

---

## 1. LIVE MONITOR - Real-time Streaming Data Visualization

Monitor your experiment as data flows in from the physics engine. Updates every 3 seconds.

### Requirements

The Quick Start above runs an installer for you. If you prefer manual install:

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
Rscript R/analysis/live_monitor.R /path/to/experiment_results.csv
```

**Example:**
```bash
./bash/run_doe.sh --exp-iterations 2 ./DOE_results &
Rscript R/analysis/live_monitor.R ./DOE_results/experiment_results.csv
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
Rscript R/analysis/complete_study.R <csv_file> [output_directory]
```

**Examples:**

```bash
# Basic usage
Rscript R/analysis/complete_study.R ./DOE_results/experiment_results.csv

# Specify output directory
Rscript R/analysis/complete_study.R ./DOE_results/experiment_results.csv ./analysis_results
```

### Generated Output

Creates an analysis directory with:

```
analysis_results/
├── doe_analysis_report.html       ← Main report (open in browser)
├── summary_statistics.csv         ← Descriptive stats by config
├── configuration_effects.csv      ← Mean effects comparison
├── window_decay_analysis.csv      ← Rolling window / decay stats
├── window_decay_correlations.csv  ← Correlations summary
├── 01_boxplots.png                ← 4-panel boxplot visualization
├── 02_distributions.png           ← Probability distributions
├── 03_effects.png                 ← Effect size comparison chart
└── 04_window_decay.png            ← Rolling window & decay visuals
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
  - Rolling window & decay relationships

---

## Workflow Example

### Full Pipeline

```bash
#!/bin/bash

# 1. Start monitoring in background
Rscript R/analysis/live_monitor.R ./DOE_results/experiment_results.csv &
MONITOR_PID=$!

# 2. Run experiment
./bash/run_nested_doe.sh --exp-iterations 2 ./DOE_results

# 3. Kill monitor
kill $MONITOR_PID

# 4. Generate complete analysis
Rscript R/analysis/complete_study.R ./DOE_results/experiment_results.csv ./doe_analysis

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
- `rolling_window_width` - Rolling window width (if present)
- `decay_slope` - Decay slope (if present)

---

## Troubleshooting

### "Error: CSV file not found"
Make sure the CSV path is correct and the file exists.

### "No data yet" in Live Monitor
The CSV might be empty. Check that your experiment has started writing data.

### Shiny app won't open
Port 3838 may be in use. Manually open http://127.0.0.1:3838 in your browser.

### HTML report not displaying images
Make sure you open the HTML file from its directory (don’t move it elsewhere first). If you move it, also move the PNGs with it.

### Missing packages
Run the one-time installer:
```bash
Rscript R/analysis/install_packages.R
```

---

## Making Scripts Executable (optional)

```bash
chmod +x R/analysis/live_monitor.R
chmod +x R/analysis/complete_study.R
```

Then you can run them as:
```bash
./R/analysis/live_monitor.R /path/to/csv
./R/analysis/complete_study.R /path/to/csv ./output_dir
```

---

## Notes

- **Live Monitor** shows rolling window of latest ~500 observations to avoid memory bloat
- **Complete Study** processes entire dataset (useful for final analysis)
- Both are non-destructive (read-only operations on CSV)
- Reports generated in HTML for easy sharing
- All statistics use `na.rm = TRUE` to handle any missing values gracefully


---

## How StarForth, StarForth-DoE, and StarForth-Governance tie together

This DoE repository is designed to work alongside two sibling repositories:

- StarForth: The VM/engine that builds the starforth binary executed by the DoE runners.
- StarForth-Governance: Policies, process, and review checklists that guide how experiments are planned, executed, and accepted.

Typical layout (recommended):

- ~/CLionProjects/StarForth
- ~/CLionProjects/StarForth-DoE  ← this repo
- ~/CLionProjects/StarForth-Governance

By default, the bash runners in this repo will try to locate the engine source in a sibling directory ../StarForth. If your StarForth engine is elsewhere, set STARFORTH_REPO_ROOT to point to it.

### Configure engine location

```bash
# If your engine lives in a non-sibling directory
export STARFORTH_REPO_ROOT=/path/to/StarForth

# Run a compact single-iteration DoE
./bash/run_doe.sh --exp-iterations 1 ./results

# Run a larger sequential DoE
./bash/run_nested_doe.sh --exp-iterations 2 ./seq_results
```

The runners will:

- Build the engine under $STARFORTH_REPO_ROOT (or ../StarForth if present, else this repo)
- Produce results under the provided output directory
- Emit randomized test matrices and per-run logs

### Governance linkage

Use StarForth-Governance to:

- Define the experiment success criteria (acceptance thresholds, stopping rules)
- Record experiment design and parameterization
- Capture sign-offs on results produced by this DoE suite

Update your governance artifacts to include links to:

- The output directory produced by these scripts (experiment_results.csv, run_logs/)
- The generated analysis from R/analysis/complete_study.R (HTML report)

This keeps the experimental data, analysis, and decision record synchronized across the three repositories.


---

## 3. One-command workflow: run + monitor + analyze

If you prefer a single command that runs the experiment, shows live charts, and then generates the final analysis when finished, use the orchestration script.

### Usage

```bash
# From repo root
./bash/run_and_monitor.sh [--exp-iterations N] OUTPUT_DIR
```

Examples:

```bash
# Quick run with live monitoring, results in ./DOE_results
./bash/run_and_monitor.sh --exp-iterations 1 ./DOE_results

# Larger run
./bash/run_and_monitor.sh --exp-iterations 2 ./DOE_results
```

What it does:
- Starts the DoE run (bash/run_doe.sh)
- Waits for experiment_results.csv to appear
- Launches the live monitor (R/analysis/live_monitor.R) against that CSV
- When the run completes, it stops the live monitor
- Executes the complete study (R/analysis/complete_study.R) and writes outputs into OUTPUT_DIR

Notes:
- You can still run live_monitor.R and complete_study.R manually if you prefer.
- The script respects the same engine discovery logic as the other runners via STARFORTH_REPO_ROOT.
- All outputs are placed under OUTPUT_DIR.
