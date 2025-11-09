#!/usr/bin/env Rscript

# One-time installer for StarForth DoE analysis dependencies
# Usage:
#   Rscript R/analysis/install_packages.R

required <- c(
  # Live monitor
  "shiny", "ggplot2", "dplyr", "tidyr",
  # Complete study
  "cowplot", "data.table"
)

installed <- rownames(installed.packages())
missing <- setdiff(required, installed)

if (length(missing) > 0) {
  cat("Installing missing packages:\n  ", paste(missing, collapse=", "), "\n", sep="")
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  cat("All required packages are already installed.\n")
}

# Verify load
ok <- sapply(required, function(pkg) {
  suppressPackageStartupMessages(require(pkg, character.only = TRUE, quietly = TRUE))
})

if (all(ok)) {
  cat("Success: all packages installed and loadable.\n")
} else {
  bad <- names(ok)[!ok]
  cat("Warning: some packages failed to load:", paste(bad, collapse=", "), "\n")
  quit(status = 1)
}
