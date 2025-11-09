#!/bin/bash

#
#                                  ***   StarForth   ***
#
#  run_and_monitor.sh - Orchestrate DoE run + live monitor + final analysis
#  Modified by - rajames
#  Last modified - 2025-11-09
#
#  This work is released into the public domain under the Creative Commons Zero v1.0 Universal license.
#  See <http://creativecommons.org/publicdomain/zero/1.0/>.
#
#  Usage:
#    ./bash/run_and_monitor.sh [--exp-iterations N] OUTPUT_DIR
#
#  Example:
#    ./bash/run_and_monitor.sh --exp-iterations 2 ./results
#
#  Behavior:
#    - Runs bash/run_doe.sh to execute the experiment.
#    - Launches R/analysis/live_monitor.R against the experiment CSV once it appears.
#    - After the run completes, stops the live monitor and executes
#      R/analysis/complete_study.R to produce full analysis artifacts in OUTPUT_DIR.
#

set -euo pipefail

EXP_ITERATIONS=1
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exp-iterations)
      EXP_ITERATIONS="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--exp-iterations N] OUTPUT_DIR"; exit 0;;
    --) shift; break;;
    -*) echo "Unknown option: $1"; exit 1;;
    *) OUTPUT_DIR="$1"; shift;;
  esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "Usage: $0 [--exp-iterations N] OUTPUT_DIR"
  exit 1
fi

# Resolve repo root and important paths
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/bash"
R_DIR="${REPO_ROOT}/R/analysis"

# Convert OUTPUT_DIR to absolute path
if [[ ! "$OUTPUT_DIR" = /* ]]; then
  OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}"
fi
mkdir -p "$OUTPUT_DIR"
CSV_PATH="${OUTPUT_DIR}/experiment_results.csv"
LOG_DIR="${OUTPUT_DIR}/run_logs"
mkdir -p "$LOG_DIR"

MONITOR_PID=""
DOE_PID=""

log() { echo -e "\033[1;34m[run_and_monitor]\033[0m $*"; }
warn() { echo -e "\033[1;33m[run_and_monitor]\033[0m $*"; }
err() { echo -e "\033[0;31m[run_and_monitor]\033[0m $*"; }

cleanup() {
  # Stop live monitor if it's still running
  if [[ -n "${MONITOR_PID}" ]] && kill -0 "${MONITOR_PID}" 2>/dev/null; then
    warn "Stopping live monitor (pid=${MONITOR_PID})"
    kill "${MONITOR_PID}" 2>/dev/null || true
    wait "${MONITOR_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_csv() {
  local path="$1"; local timeout="$2"; local waited=0
  while [[ ! -f "$path" ]]; do
    if (( waited >= timeout )); then
      return 1
    fi
    sleep 1; waited=$((waited+1))
  done
  return 0
}

# Kick off the DoE run in background so we can start the monitor when CSV appears
log "Launching DoE run: --exp-iterations ${EXP_ITERATIONS} -> ${OUTPUT_DIR}"
"${SCRIPT_DIR}/run_doe.sh" --exp-iterations "${EXP_ITERATIONS}" "${OUTPUT_DIR}" &
DOE_PID=$!

# Wait for the CSV header to appear (run_doe.sh initializes it early)
log "Waiting for CSV to become available at ${CSV_PATH} ..."
if wait_for_csv "${CSV_PATH}" 120; then
  log "CSV detected. Starting live monitor."
  Rscript "${R_DIR}/live_monitor.R" "${CSV_PATH}" &
  MONITOR_PID=$!
  log "Live monitor running (pid=${MONITOR_PID})."
else
  warn "CSV not found within timeout; proceeding without live monitoring."
fi

# Wait for DoE to finish
wait "${DOE_PID}"
log "DoE run completed."

# Stop the monitor if running
cleanup

# Run complete analysis
log "Running complete analysis..."
Rscript "${R_DIR}/complete_study.R" "${CSV_PATH}" "${OUTPUT_DIR}" || {
  err "Complete analysis failed. Check R output above."
  exit 1
}

REPORT_HTML="${OUTPUT_DIR}/doe_analysis_report.html"
if [[ -f "${REPORT_HTML}" ]]; then
  log "Analysis complete. Report: ${REPORT_HTML}"
else
  warn "Expected report not found at ${REPORT_HTML}. Check analysis output directory."
fi

log "All done. Outputs in: ${OUTPUT_DIR}"
