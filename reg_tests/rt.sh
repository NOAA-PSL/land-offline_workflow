#!/bin/bash
set -e
set -o pipefail

# 1. Locate directories
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"
LOG_FILE="${SCRIPT_DIR}/summary.log"

# Remove summary.log if it exists from a previous run
rm -f "$LOG_FILE"

# ----------------------------------------------------------------------
# DEFINE YOUR TEST CASES HERE
# Format: "cycle_settings_file  da_settings_file  verification_script"
# ----------------------------------------------------------------------
TEST_CASES=(
    "settings_cycle_test_C96_snow_letkf settings_snowDA_test_letkf  check_C96_letkf_snowDA_test.sh"
    "settings_cycle_test_C96_snow_2dvar settings_snowDA_test_2dvar  check_C96_2dvar_snowDA_test.sh"
#    "settings_cycle_test_soil settings_soilDA_test  check_soilDA_test.sh"
)

# Global cleanup function to remove staged symlinks on unexpected aborts
cleanup() {
    for TEST in "${TEST_CASES[@]}"; do
        read -r CYCLE_CFG DA_CFG _ <<< "$TEST"
        rm -f "${REPO_DIR}/${CYCLE_CFG}" "${REPO_DIR}/${DA_CFG}"
    done
}
trap cleanup EXIT

# Wrap the entire test execution matrix for logging
{
    echo "=================================================="
    echo " Starting Flexible Regression Test Suite          "
    echo " Total test scenarios detected: ${#TEST_CASES[@]} "
    echo "=================================================="

    PASSED_SCENARIOS=()
    FAILED_SCENARIOS=()

    for TEST in "${TEST_CASES[@]}"; do
        # Parse space-separated definitions
        read -r CYCLE_CFG DA_CFG CHECK_SCR <<< "$TEST"

        echo ""
        echo "--------------------------------------------------"
        echo " RUNNING SCENARIO: $CYCLE_CFG + $DA_CFG"
        echo "--------------------------------------------------"

        # Verify files exist in reg_tests before executing
        if [ ! -f "${SCRIPT_DIR}/${CYCLE_CFG}" ] || [ ! -f "${SCRIPT_DIR}/${DA_CFG}" ] || [ ! -f "${SCRIPT_DIR}/${CHECK_SCR}" ]; then
            echo "ERROR: Missing required components for this scenario in reg_tests/."
            echo "Skipping configuration..."
            FAILED_SCENARIOS+=("$CYCLE_CFG ($DA_CFG) - Missing Files")
            continue
        fi

        # Stage files to repository root where workflow scripts expect them
        ln -sf "${SCRIPT_DIR}/${CYCLE_CFG}" "${REPO_DIR}/${CYCLE_CFG}"
        ln -sf "${SCRIPT_DIR}/${DA_CFG}" "${REPO_DIR}/${DA_CFG}"

        # Switch context to repository root directory
        cd "$REPO_DIR"

        # Execute compiled test preparation logic
        source "./${CYCLE_CFG}"                  # Loads OUTDIR and exp_name variables [cite: 2, 9]
        rm -rf "${OUTDIR}"                       # Clear previous evaluation outputs [cite: 2, 9]

        echo "Submitting cycle workflow..."
        # Pass the unique cycle configuration file directly to the runner script 
        SUBMIT_OUTPUT=$(./do_submit_cycle.sh "${CYCLE_CFG}" 2>&1)
        echo "$SUBMIT_OUTPUT"

        # Extract Job ID from submission message
        JOB_ID=$(echo "$SUBMIT_OUTPUT" | grep -i "Submitted batch job" | grep -oE '[0-9]+' | head -n 1)

        echo "Monitoring task queue status..."
        if [ -n "$JOB_ID" ]; then
            echo "--> Tracking Slurm Job ID: $JOB_ID"
            sleep 10
            while squeue -j "$JOB_ID" 2>/dev/null | grep -q "$JOB_ID"; do
                sleep 30
            done
	    #comment out for debug (when needed) by retaining all log files
            echo "Cleaning up scheduler log files"
            rm -f "${REPO_DIR}"/err_*.[0-9]* "${REPO_DIR}"/log_*.[0-9]* "${REPO_DIR}/cycle.log"
        else
            echo "--> Tracking by experiment name fallback: $exp_name [cite: 2, 9]"
            sleep 10
            while squeue -u "$USER" -o "%j" 2>/dev/null | grep -q "${exp_name}"; do
                sleep 30
            done
            rm -f "${REPO_DIR}"/err_*.[0-9]* "${REPO_DIR}"/log_*.[0-9]* "${REPO_DIR}/cycle.log" 2>/dev/null || true
        fi

        echo "Job sequence concluded. Executing verification script..."
        
        # Execute verification script out of the reg_tests directory context
        set +e
        "${SCRIPT_DIR}/${CHECK_SCR}"
        CHECK_RC=$?
        set -e

        if [ $CHECK_RC -eq 0 ]; then
            echo "Result: SCENARIO PASSED"
            PASSED_SCENARIOS+=("$CYCLE_CFG ($DA_CFG)")
        else
            echo "Result: SCENARIO FAILED"
            FAILED_SCENARIOS+=("$CYCLE_CFG ($DA_CFG)")
        fi

        # Remove symlinks immediately after scenario finishes to prevent cross-contamination
        rm -f "${REPO_DIR}/${CYCLE_CFG}" "${REPO_DIR}/${DA_CFG}"
    done

    # ------------------------------------------------------------------
    # FINAL REPORT CARD GENERATION
    # ------------------------------------------------------------------
    echo ""
    echo "=================================================="
    echo " REGRESSION TEST RESULTS SUMMARY                  "
    echo "=================================================="
    
    if [ ${#PASSED_SCENARIOS[@]} -gt 0 ]; then
        echo "PASSED:"
        for PASSED in "${PASSED_SCENARIOS[@]}"; do
            echo "  - $PASSED"
        done
    fi

    if [ ${#FAILED_SCENARIOS[@]} -gt 0 ]; then
        echo "FAILED:"
        for FAILED in "${FAILED_SCENARIOS[@]}"; do
            echo "  - $FAILED"
        done
        echo "=================================================="
        echo " STATUS: REGRESSION TEST FAILED "
        echo "=================================================="
        exit 1
    else
        echo "=================================================="
        echo " STATUS: REGRESSION TEST PASSED "
        echo "=================================================="
        exit 0
    fi

} 2>&1 | tee "$LOG_FILE"
