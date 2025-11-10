# StarForth DoE Analysis - Quick Start

## One-Minute Setup

```bash
# 1. Install R packages (one-time only)
Rscript -e "install.packages(c('shiny', 'ggplot2', 'dplyr', 'tidyr', 'cowplot', 'data.table'))"

# 2. Make scripts executable
chmod +x live_monitor.R complete_study.R
```

## Two-Phase Workflow

StarForth DoE runs now store results directly in this repo under `./experiments/<LABEL>/`
(`experiment_results.csv` plus `run_logs/`). Treat each label (`DOE_01`, `TST_02`, etc.)
as a lab-book entry and keep the final analysis next to it.

### Phase 1: LIVE MONITORING (During Experiment)

```bash
# Start in background (label, directory, or explicit CSV)
./live_monitor.R DOE_01 &

# Run your experiment (writes into ./experiments/DOE_01/)
./scripts/run_doe.sh --exp-iterations 2 DOE_01

# Monitor opens at: http://127.0.0.1:3838 (auto-refresh every 3s)
```

**Live Monitor Shows:**
- Real-time observation counts by configuration
- Cache Hit % and Bucket Hit % boxplots
- Time series trends
- Summary statistics table

### Phase 2: COMPLETE ANALYSIS (After Experiment)

```bash
# Once experiment finishes (keep analysis with the run):
./complete_study.R experiments/DOE_01/experiment_results.csv \\
                   experiments/DOE_01/analysis

# Opens analysis report:
open experiments/DOE_01/analysis/doe_analysis_report.html
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
./live_monitor.R DOE_01 &
MONITOR_PID=$!

echo "Live monitor running at http://127.0.0.1:3838"

# Run nested DoE experiment
./scripts/run_nested_doe.sh --exp-iterations 2 DOE_01

# Stop monitor
kill $MONITOR_PID

# Generate complete analysis
./complete_study.R experiments/DOE_01/experiment_results.csv \\
                   experiments/DOE_01/analysis

# Display results
echo "Analysis complete. Open: experiments/DOE_01/analysis/doe_analysis_report.html"
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
experiments/DOE_01/analysis/
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
