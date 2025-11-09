#!/bin/bash

#
#                                  ***   StarForth   ***
#
#  run_nested_doe.sh - FORTH-79 Standard and ANSI C99 ONLY
#  Sequential DoE with per-config build & randomized test execution
#  Modified by - rajames
#  Last modified - 2025-11-08
#
#  Copyright (c) 2025 (rajames) Robert A. James - StarshipOS Forth Project.
#
#  This work is released into the public domain under the Creative Commons Zero v1.0 Universal license.
#  To the extent possible under law, the author(s) have dedicated all copyright and related
#  and neighboring rights to this software to the public domain worldwide.
#  This software is distributed without any warranty.
#
#  See <http://creativecommons.org/publicdomain/zero/1.0/> for more information.
#
#  /home/rajames/CLionProjects/StarForth-DoE/bash/run_nested_doe.sh
#

################################################################################
#
#  StarForth Physics Engine Sequential Nested DoE
#
#  Design of Experiments with Sequential Config Testing & Randomized Execution
#
#  Model: (30 * ITERATIONS * 4) randomized tests per CONFIG
#
#  Four Sequential Configurations:
#  ───────────────────────────────────────────────────────────────
#  Config 1: A_BASELINE (no optimizations)
#    - Build once
#    - Run (30 * X * 4) randomized iterations
#    - Provides baseline control
#
#  Config 2: A_B_CACHE (hotwords cache only)
#    - Build once
#    - Run (30 * X * 4) randomized iterations
#    - Isolates cache effect
#
#  Config 3: A_C_FULL (pipelining only)
#    - Build once
#    - Run (30 * X * 4) randomized iterations
#    - Isolates Loop #4 pipelining effect
#
#  Config 4: A_B_C_FULL (cache + pipelining)
#    - Build once
#    - Run (30 * X * 4) randomized iterations
#    - Full optimization stack
#
#  Total Runs: (30 * X * 4) * 4 = 120 * X * 4
#    X=1: 480 total runs
#    X=2: 960 total runs
#    X=3: 1440 total runs
#
#  Key Advantage:
#    - Sequential: Build A_BASELINE, run all tests, then move to A_B_CACHE
#    - No build thrashing (each config built exactly once)
#    - Clean separation between configs
#    - Randomized execution order within each config eliminates temporal bias
#
#  Usage:
#    ./bash/run_nested_doe.sh --exp-iterations 1 ./results
#    ./bash/run_nested_doe.sh --exp-iterations 2 ./results
#
#  Output:
#    - experiment_results.csv (rows per run with 35+ metrics)
#    - run_logs/ (detailed per-run logs)
#    - experiment_summary.txt (execution metadata)
#    - test_matrix_${CONFIG}.txt (randomized execution matrix per config)
#
#  Expected runtime:
#    X=1: ~2-3 hours (480 runs)
#    X=2: ~4-6 hours (960 runs)
#    X=3: ~6-9 hours (1440 runs)
#
################################################################################

set -e

# Parse command-line arguments
if [[ "$1" == "--exp-iterations" ]]; then
    EXP_ITERATIONS="$2"
    OUTPUT_DIR="${3:-.}"
else
    echo "Usage: $0 --exp-iterations <N> [OUTPUT_DIR]"
    echo ""
    echo "  --exp-iterations N: Number of iterations (e.g., 1, 2, 3)"
    echo "  OUTPUT_DIR:         Output directory (default: current directory)"
    echo ""
    echo "Example:"
    echo "  $0 --exp-iterations 2 ./results"
    echo ""
    echo "Model: (30 * N * 4) randomized tests per CONFIG × 4 CONFIGS"
    echo "Total runs: 120 * N * 4"
    echo "  N=1: 480 runs"
    echo "  N=2: 960 runs"
    echo "  N=3: 1440 runs"
    exit 1
fi

# Validate iterations
if ! [[ "$EXP_ITERATIONS" =~ ^[0-9]+$ ]] || [ "$EXP_ITERATIONS" -lt 1 ]; then
    echo "Error: --exp-iterations must be a positive integer"
    exit 1
fi

BUILD_PROFILE="fastest"
RUNS_PER_ITERATION=30
RANDOMIZATIONS_PER_RUN=4
RUNS_PER_CONFIG=$((RUNS_PER_ITERATION * EXP_ITERATIONS * RANDOMIZATIONS_PER_RUN))
TOTAL_RUNS=$((RUNS_PER_CONFIG * 4))

# Paths - must be run from this repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Location of the StarForth engine source (can be separate repo)
# Set STARFORTH_REPO_ROOT to override; otherwise default to sibling ../StarForth if present, else this repo
if [ -n "${STARFORTH_REPO_ROOT}" ] && [ -d "${STARFORTH_REPO_ROOT}" ]; then
    ENGINE_ROOT="${STARFORTH_REPO_ROOT}"
else
    if [ -d "${REPO_ROOT}/../StarForth" ]; then
        ENGINE_ROOT="$(cd "${REPO_ROOT}/../StarForth" && pwd)"
    else
        ENGINE_ROOT="${REPO_ROOT}"
    fi
fi
BUILD_DIR="${ENGINE_ROOT}/build"

# Convert OUTPUT_DIR to absolute path
if [[ ! "${OUTPUT_DIR}" = /* ]]; then
    OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}"
fi

LOG_DIR="${OUTPUT_DIR}/run_logs"
RESULTS_CSV="${OUTPUT_DIR}/experiment_results.csv"
SUMMARY_LOG="${OUTPUT_DIR}/experiment_summary.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure output directories exist
mkdir -p "${LOG_DIR}"
mkdir -p "${OUTPUT_DIR}"

################################################################################
# Helper Functions
################################################################################

log_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

log_section() {
    echo -e "\n${BLUE}>>> $1${NC}"
}

timestamp() {
    date +"%Y-%m-%dT%H:%M:%S"
}

runtime_seconds() {
    local start=$1
    local end=$2
    echo $((end - start))
}

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%dh %dm %ds" $hours $minutes $secs
}

extract_final_csv_row() {
    local log_file=$1
    if [ ! -f "${log_file}" ]; then
        return 1
    fi
    awk 'NF {line=$0} END {if (length(line)) print line}' "${log_file}"
}

################################################################################
# CSV Functions
################################################################################

init_csv_header() {
    # Create CSV header with metadata + full metrics from engine CSV (32 fields)
    # The engine (metrics_write_csv_header in src/doe_metrics.c) emits the fields below in this exact order.
    # We prefix with our 3 metadata columns: timestamp, configuration, run_number.
    cat > "${RESULTS_CSV}" << 'EOF'
timestamp,configuration,run_number,total_lookups,cache_hits,cache_hit_percent,bucket_hits,bucket_hit_percent,cache_hit_latency_ns,cache_hit_stddev_ns,bucket_search_latency_ns,bucket_search_stddev_ns,context_predictions_total,context_correct,context_accuracy_percent,rolling_window_width,decay_slope,hot_word_count,stale_word_ratio,avg_word_heat,prefetch_accuracy_percent,prefetch_attempts,prefetch_hits,window_tuning_checks,final_effective_window_size,vm_workload_duration_ns_q48,cpu_temp_delta_c_q48,cpu_freq_delta_mhz_q48,decay_rate_q16,decay_min_interval_ns,rolling_window_size,adaptive_shrink_rate,heat_cache_demotion_threshold,enable_hotwords_cache,enable_pipelining
EOF
    log_success "CSV header created: ${RESULTS_CSV}"
}

################################################################################
# Build Functions
################################################################################

build_configuration() {
    local config_name=$1
    local cache_flag=$2
    local pipeline_flag=$3

    log_section "Building Configuration: ${config_name}" >&2

    cd "${REPO_ROOT}"

    # Clean previous build
    make clean > /dev/null 2>&1 || true

    # Build with specific configuration
    log_info "Building: make TARGET=${BUILD_PROFILE} ENABLE_HOTWORDS_CACHE=${cache_flag} ENABLE_PIPELINING=${pipeline_flag}" >&2

    if make TARGET="${BUILD_PROFILE}" \
            ENABLE_HOTWORDS_CACHE="${cache_flag}" \
            ENABLE_PIPELINING="${pipeline_flag}" \
            > "${LOG_DIR}/build_${config_name}.log" 2>&1; then
        log_success "Build completed for ${config_name}" >&2
        echo "${BUILD_DIR}/amd64/${BUILD_PROFILE}/starforth"
    else
        log_error "Build failed for ${config_name}" >&2
        cat "${LOG_DIR}/build_${config_name}.log" >&2
        return 1
    fi
}

################################################################################
# Configuration Mapping
################################################################################

config_to_flags() {
    local config=$1
    case "${config}" in
        A_BASELINE)
            echo "0,0"  # cache=0, pipeline=0
            ;;
        A_B_CACHE)
            echo "1,0"  # cache=1, pipeline=0
            ;;
        A_C_FULL)
            echo "0,1"  # cache=0, pipeline=1
            ;;
        A_B_C_FULL)
            echo "1,1"  # cache=1, pipeline=1
            ;;
        *)
            echo "0,0"
            ;;
    esac
}

################################################################################
# Test Execution
################################################################################

generate_randomized_matrix() {
    local config_name=$1
    local num_runs=$2
    local matrix_file="${LOG_DIR}/test_matrix_${config_name}.txt"

    > "${matrix_file}"  # Clear file

    # Generate one entry per run (dummy run number from 1 to num_runs)
    for i in $(seq 1 ${num_runs}); do
        echo "${config_name},${i}" >> "${matrix_file}"
    done

    # Shuffle the matrix (randomize order)
    sort -R "${matrix_file}" > "${matrix_file}.shuffled"
    mv "${matrix_file}.shuffled" "${matrix_file}"

    echo "${matrix_file}"
}

run_single_iteration() {
    local binary=$1
    local config=$2
    local run_num=$3
    local output_log=$4

    # Execute binary with --doe-experiment flag
    if "${binary}" --doe-experiment > "${output_log}" 2>&1; then
        return 0
    else
        return 1
    fi
}

run_config_tests() {
    local config_name=$1
    local binary=$2
    local num_runs=$3

    log_header "Testing Configuration: ${config_name} (${num_runs} randomized runs)"

    # Generate randomized test matrix for this config
    local matrix_file
    if ! matrix_file=$(generate_randomized_matrix "${config_name}" "${num_runs}"); then
        log_error "Failed to generate test matrix for ${config_name}"
        return 1
    fi
    log_success "Test matrix generated: ${matrix_file}"

    # Show preview
    log_info "Test matrix preview (first 5):"
    head -5 "${matrix_file}" | sed 's/^/  /'

    # Execute all tests for this config
    local run_index=0
    while IFS=',' read -r cfg_name run_number; do
        run_index=$((run_index + 1))

        local run_log="${LOG_DIR}/${config_name}_run_${run_number}.log"
        local start_time=$(date +%s)

        log_info "Run ${run_index}/${num_runs} - ${config_name} #${run_number}..."

        if run_single_iteration "${binary}" "${config_name}" "${run_number}" "${run_log}"; then
            # Extract CSV row from log
            local csv_row
            if ! csv_row=$(extract_final_csv_row "${run_log}"); then
                log_error "Run ${run_index}/${num_runs} missing metrics row - check ${run_log}"
                return 1
            fi

            if [ -z "${csv_row}" ]; then
                log_error "Run ${run_index}/${num_runs} produced empty metrics row - check ${run_log}"
                return 1
            fi

            # Append to CSV
            local ts_now=$(timestamp)
            echo "${ts_now},${config_name},${run_number},${csv_row}" >> "${RESULTS_CSV}"

            local elapsed=$(runtime_seconds ${start_time} $(date +%s))
            log_success "Run ${run_index}/${num_runs} completed (${elapsed}s)"
        else
            log_error "Run ${run_index}/${num_runs} failed - check ${run_log}"
            return 1
        fi

    done < "${matrix_file}"

    log_success "All ${num_runs} runs completed for ${config_name}!"
}

################################################################################
# Main Execution
################################################################################

main() {
    local experiment_start=$(date +%s)
    local start_time=$(timestamp)

    log_header "STARFORTH PHYSICS ENGINE SEQUENTIAL NESTED DoE"
    log_info "Iterations: ${EXP_ITERATIONS}"
    log_info "Runs per config: ${RUNS_PER_CONFIG} (30 × ${EXP_ITERATIONS} × 4)"
    log_info "Total runs: ${TOTAL_RUNS} (${RUNS_PER_CONFIG} × 4 configs)"
    log_info "Build profile: ${BUILD_PROFILE}"

    echo "" > "${SUMMARY_LOG}"
    echo "Sequential Nested DoE Experiment" >> "${SUMMARY_LOG}"
    echo "Start time: ${start_time}" >> "${SUMMARY_LOG}"
    echo "Iterations: ${EXP_ITERATIONS}" >> "${SUMMARY_LOG}"
    echo "Runs per config: ${RUNS_PER_CONFIG}" >> "${SUMMARY_LOG}"
    echo "Total runs: ${TOTAL_RUNS}" >> "${SUMMARY_LOG}"
    echo "" >> "${SUMMARY_LOG}"

    # Initialize CSV
    init_csv_header

    # Define configurations
    local configs=("A_BASELINE" "A_B_CACHE" "A_C_FULL" "A_B_C_FULL")

    # Process each configuration sequentially
    local total_completed=0
    for config in "${configs[@]}"; do
        log_header "CONFIGURATION: ${config}"

        # Get flags for this config
        local flags=$(config_to_flags "${config}")
        local cache_flag="${flags%,*}"
        local pipeline_flag="${flags#*,}"

        # Build this config
        local binary
        if ! binary=$(build_configuration "${config}" "${cache_flag}" "${pipeline_flag}"); then
            log_error "Failed to build ${config}"
            return 1
        fi
        log_success "Binary ready: ${binary}"

        # Run all tests for this config
        if ! run_config_tests "${config}" "${binary}" "${RUNS_PER_CONFIG}"; then
            log_error "Tests failed for ${config}"
            return 1
        fi

        total_completed=$((total_completed + RUNS_PER_CONFIG))
        local pct=$((total_completed * 100 / TOTAL_RUNS))
        log_info "Progress: ${total_completed}/${TOTAL_RUNS} runs completed (${pct}%)"
    done

    # Summary
    local experiment_end=$(date +%s)
    local total_seconds=$(runtime_seconds ${experiment_start} ${experiment_end})
    local end_time=$(timestamp)

    log_header "EXPERIMENT COMPLETE"
    log_success "All ${TOTAL_RUNS} runs completed successfully!"
    log_success "Results saved to: ${RESULTS_CSV}"
    log_success "Total runtime: $(format_duration ${total_seconds})"
    log_success "Run logs: ${LOG_DIR}/"

    echo "" >> "${SUMMARY_LOG}"
    echo "End time: ${end_time}" >> "${SUMMARY_LOG}"
    echo "Total runtime: $(format_duration ${total_seconds})" >> "${SUMMARY_LOG}"
    echo "Results: ${RESULTS_CSV}" >> "${SUMMARY_LOG}"
    echo "Logs: ${LOG_DIR}/" >> "${SUMMARY_LOG}"

    # Show CSV preview
    log_info "CSV Results Preview (first 5 data rows):"
    head -6 "${RESULTS_CSV}" | sed 's/^/  /'

    return 0
}

# Execute
main "$@"
exit $?