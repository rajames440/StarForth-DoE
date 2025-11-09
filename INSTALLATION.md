# StarForth DoE Analysis Suite - Installation & Setup

## Files Provided

```
StarForth-DoE/
├── live_monitor.R              ← Live real-time monitoring app
├── complete_study.R            ← Complete statistical analysis
├── README.md                   ← Full documentation
├── QUICKSTART.md               ← Quick reference guide
└── INSTALLATION.md             ← This file
```

---

## Installation

### Step 1: Verify R is Installed

```bash
R --version
# Should output something like: R version 4.x.x
```

### Step 2: Install Required R Packages

**One-time setup:**

```bash
Rscript -e "
packages <- c('shiny', 'ggplot2', 'dplyr', 'tidyr', 'cowplot', 'data.table')
install.packages(packages)
"
```

Or interactively in R:
```r
install.packages(c('shiny', 'ggplot2', 'dplyr', 'tidyr', 'cowplot', 'data.table'))
```

### Step 3: Verify Installation

```bash
Rscript -e "
library(shiny)
library(ggplot2)
library(dplyr)
library(tidyr)
library(cowplot)
library(data.table)
cat('All packages loaded successfully!\n')
"
```

Expected output: `All packages loaded successfully!`

---

## Usage

### Option 1: As Direct Scripts

```bash
# Live Monitor
Rscript live_monitor.R /path/to/experiment_results.csv

# Complete Study
Rscript complete_study.R /path/to/experiment_results.csv ./output_dir
```

### Option 2: As Executable Scripts (Recommended)

```bash
# Make executable
chmod +x live_monitor.R complete_study.R

# Run directly
./live_monitor.R /path/to/experiment_results.csv
./complete_study.R /path/to/experiment_results.csv ./output_dir
```

### Option 3: Full Automated Pipeline

Create `run_analysis.sh`:
```bash
#!/bin/bash

# Configuration
CSV_FILE="./results/experiment_results.csv"
ANALYSIS_DIR="./doe_analysis"

echo "Starting Live Monitor..."
./live_monitor.R "$CSV_FILE" &
MONITOR_PID=$!

echo "Live Monitor running (PID: $MONITOR_PID)"
echo "Open http://127.0.0.1:3838 to view real-time data"

# Run your experiment here
echo "Waiting for experiment completion..."
wait

# Kill monitor
kill $MONITOR_PID

# Generate report
echo "Running complete analysis..."
./complete_study.R "$CSV_FILE" "$ANALYSIS_DIR"

echo "Analysis complete!"
echo "Open: $ANALYSIS_DIR/doe_analysis_report.html"
```

Then run:
```bash
chmod +x run_analysis.sh
./run_analysis.sh
```

---

## Data Format

Both scripts expect the standard CSV output from `run_doe.sh` or `run_nested_doe.sh`:

```csv
timestamp,configuration,run_number,total_lookups,cache_hits,cache_hit_percent,...
2025-11-09T05:55:28,A_B_CACHE,9,3865,0,0.00,...
...
```

### Required Columns

- `timestamp` - ISO 8601 timestamp
- `configuration` - One of: A_BASELINE, A_B_CACHE, A_C_FULL, A_B_C_FULL
- `cache_hit_percent` - Cache performance metric
- `bucket_hit_percent` - Bucket lookup performance
- `context_accuracy_percent` - Prediction accuracy
- `vm_workload_duration_ns_q48` - Workload duration

The scripts are forgiving of extra columns - they extract only what they need.

---

## Troubleshooting

### Issue: "package 'X' is not available for R version"

**Solution:** Update R and packages
```bash
R --version  # Check your R version (need 3.6+)
# If too old, install latest R from https://www.r-project.org/
```

### Issue: "Error in library(shiny)"

**Solution:** Install the package
```bash
Rscript -e "install.packages('shiny')"
```

### Issue: Shiny app won't open at 127.0.0.1:3838

**Solution:** Port may be in use. Try:
- Use a different port by modifying the script (see README)
- Kill other R processes: `pkill -9 R`
- Check firewall settings

### Issue: "Error: could not find function X"

**Solution:** Install missing packages
```bash
# Find which package is missing and install
Rscript -e "install.packages('package_name')"
```

### Issue: CSV "more columns than column names"

**Solution:** This is handled automatically. The scripts use `data.table::fread()` which is forgiving of malformed CSVs with extra columns.

---

## Performance Notes

- **Live Monitor**: Handles up to ~500 concurrent observations before performance degrades
- **Complete Study**: Processes entire dataset (tested with 1000+ observations)
- **Visualizations**: PNG generation takes ~3-5 seconds per plot
- **Memory**: Minimal usage (~200MB for 1000 observations)

---

## Output Files

### live_monitor.R (Interactive Web App)
- Runs at: `http://127.0.0.1:3838`
- Shows live updating plots and tables
- Refreshes every 3 seconds

### complete_study.R (Static Report + Analysis)

**Generated Files:**
```
doe_analysis/
├── doe_analysis_report.html        (67 KB)  ← Main report
├── summary_statistics.csv          (360 B)  ← Summary table
├── configuration_effects.csv       (213 B)  ← Effects table
├── 01_boxplots.png                 (532 KB) ← Distribution plots
├── 02_distributions.png            (293 KB) ← Density plots
└── 03_effects.png                  (100 KB) ← Effect size chart
```

---

## Next Steps

1. **Read QUICKSTART.md** for a 2-minute workflow overview
2. **Read README.md** for detailed feature documentation
3. **Run on your data**: `./complete_study.R your_data.csv ./analysis_output`
4. **Share results**: All PNG files are publication-ready

---

## Support

If you encounter issues:

1. Check that R and packages are properly installed
2. Verify CSV file exists and is readable
3. Check file permissions: `ls -l your_data.csv`
4. Review error messages carefully
5. Try step-by-step installation verification above

