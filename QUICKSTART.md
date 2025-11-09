# StarForth DoE Analysis - Quick Start

## One-Minute Setup

```bash
# 1. Install R packages (one-time only)
Rscript -e "install.packages(c('shiny', 'ggplot2', 'dplyr', 'tidyr', 'cowplot', 'data.table'))"

# 2. Make scripts executable
chmod +x live_monitor.R complete_study.R
```

## Two-Phase Workflow

### Phase 1: LIVE MONITORING (During Experiment)

```bash
# Start in background
./live_monitor.R /path/to/experiment_results.csv &

# Run your experiment
./scripts/run_doe.sh --exp-iterations 2 ./results

# Monitor opens at: http://127.0.0.1:3838
# Updates every 3 seconds with streaming data
```

**Live Monitor Shows:**
- Real-time observation counts by configuration
- Cache Hit % and Bucket Hit % boxplots
- Time series trends
- Summary statistics table

### Phase 2: COMPLETE ANALYSIS (After Experiment)

```bash
# Once experiment finishes:
./complete_study.R ./results/experiment_results.csv ./analysis_output

# Opens analysis report:
open ./analysis_output/doe_analysis_report.html
```

**Report Contains:**
- ✓ Descriptive statistics (N, mean, SD, min, max)
- ✓ ANOVA tests for each metric
- ✓ Post-hoc pairwise comparisons (Tukey HSD)
- ✓ Configuration effects analysis
- ✓ 3x publication-quality visualizations
- ✓ CSV exports for further analysis

---

## Example: Full Pipeline

```bash
#!/bin/bash

# Start live monitor in background
./live_monitor.R ./DOE_results/experiment_results.csv &
MONITOR_PID=$!

echo "Live monitor running at http://127.0.0.1:3838"

# Run nested DoE experiment
./scripts/run_nested_doe.sh --exp-iterations 2 ./DOE_results

# Stop monitor
kill $MONITOR_PID

# Generate complete analysis
./complete_study.R ./DOE_results/experiment_results.csv ./doe_analysis

# Display results
echo "Analysis complete. Open: ./doe_analysis/doe_analysis_report.html"
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "No module named shiny" | Run: `Rscript -e "install.packages('shiny')"` |
| Shiny app won't open | Try: `http://127.0.0.1:3838` or use different port |
| CSV read errors | Ensure CSV exists and is properly formatted |
| Graphics won't display | Check that analysis output files exist and permissions |

---

## What Gets Generated

```
analysis_output/
├── doe_analysis_report.html         ← Main report (open in browser)
├── summary_statistics.csv           ← Stats by configuration
├── configuration_effects.csv        ← Mean effects comparison
├── 01_boxplots.png                  ← 4-panel distribution plots
├── 02_distributions.png             ← Probability distributions
└── 03_effects.png                   ← Effect size bar chart
```

---

## Key Metrics Analyzed

- **Cache Hit %**: Impact of hotwords cache optimization
- **Bucket Hit %**: Hash bucket lookup performance
- **Context Accuracy %**: Prediction accuracy metric
- **VM Workload Duration**: Total execution time
- **Latency**: Cache lookup latency characteristics

---

## Next Steps After Analysis

1. **Review the HTML report** - get instant visual overview
2. **Export CSV files** - for integration with other tools
3. **Share visualizations** - PNG files are publication-ready
4. **Run follow-up experiments** - iterate based on findings

