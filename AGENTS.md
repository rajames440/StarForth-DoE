# Repository Guidelines

## Project Structure & Module Organization
- `R/analysis/` contains the core R scripts: `live_monitor.R` (real-time Shiny app), `complete_study.R` (post-run statistics), and `install_packages.R` (dependency bootstrap).
- `bash/` holds automation entrypoints (`run_doe.sh`, `run_nested_doe.sh`, `run_and_monitor.sh`) that orchestrate physics-engine runs plus monitoring.
- `experiments/<LABEL>/` is the canonical "lab book" for raw CSV telemetry and `run_logs/`; keep each label self-contained.
- `outputs/<LABEL>/` stores rendered HTML/PNG artifacts outside the mutable experiment folder.
- `README.md` and `QUICKSTART.md` document the workflow; update both whenever stages or asset names change.

## Build, Test, and Development Commands
- `Rscript R/analysis/install_packages.R` installs CRAN libraries; run after cloning or whenever dependencies shift.
- `bash/run_doe.sh DOE_01` (or `run_nested_doe.sh`) launches an experiment and writes into `experiments/DOE_01/`.
- `Rscript R/analysis/live_monitor.R DOE_01` tails the freshest CSV and refreshes the dashboard every 3 seconds.
- `Rscript R/analysis/complete_study.R experiments/DOE_01/experiment_results.csv experiments/DOE_01/analysis` produces the statistical report; the second argument is the output directory.

## Coding Style & Naming Conventions
- Follow tidyverse-style R: two-space indentation within blocks, `snake_case` for objects (`load_latest_data`, `cache_hit_percent`), and guard every script with `#!/usr/bin/env Rscript`.
- Prefer `dplyr` pipelines over base loops for wrangling; keep plotting logic in helper functions so monitor and study scripts stay aligned.
- Bash scripts should start with `#!/usr/bin/env bash`, `set -euo pipefail`, and use descriptive lowercase function names; environment variables stay UPPER_SNAKE_CASE.
- Lab labels are uppercase with numeric suffixes (e.g., `DOE_07`, `EXP_12`) so tooling can sort chronologically.

## Testing Guidelines
- There is no automated test harness; validate changes with CSVs under `experiments/DOE_00/` or purpose-built fixtures committed with the branch.
- After touching analysis code, regenerate a report via `complete_study.R` and confirm the HTML plus `summary_statistics.csv` and `configuration_effects.csv` appear in `outputs/<LABEL>/`.
- For live updates, run `live_monitor.R` against a file that is still being appended and verify the plots refresh without console errors.
- Document new metrics or columns directly in the resulting report so reviewers can compare expected values.

## Commit & Pull Request Guidelines
- Mirror the existing history: short, imperative, sentence-case commit subjects (e.g., `Add IntelliJ configuration files and update scripts for streamlined experiment management.`). Batch related file changes per commit.
- Every PR should include purpose, rerun commands, a sample lab label (or sanitized CSV), and screenshots or key figures when the UI/report changes.
- Link GitHub issues or lab notebook IDs when relevant, and flag data-retention or privacy considerations in the PR description before requesting review.
