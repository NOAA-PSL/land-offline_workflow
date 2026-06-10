#!/bin/bash

#------------------------------------------------------------------
# Check Snow DA Regression Test Results
#
# This script validates the results of all completed snow DA tests
# by comparing outputs against baseline data using nccmp.
#
# Usage: ./check_snowDA_tests.sh
#        or automatically called after test job completes
#------------------------------------------------------------------

set -x

echo "========================================"
echo "Snow DA Test Results Check"
echo "========================================"
echo ""

# Get directories
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/../../" && pwd )"

echo "Script dir: ${SCRIPT_DIR}"
echo "RT dir: ${RT_DIR}"
echo "Root dir: ${ROOT_DIR}"
echo ""

# Source rt.control for baseline and test directories
if [[ -f "${RT_DIR}/rt.control" ]]; then
    source ${RT_DIR}/rt.control
else
    echo "ERROR: Cannot find rt.control at ${RT_DIR}/rt.control"
    exit 1
fi

# Source snow DA settings
if [[ -f "${ROOT_DIR}/settings_snowDA_test" ]]; then
    source ${ROOT_DIR}/settings_snowDA_test
else
    echo "ERROR: Cannot find settings_snowDA_test at ${ROOT_DIR}/settings_snowDA_test"
    exit 1
fi

echo "Test directory: ${DATA}"
echo "Baseline directory: ${HOMEreg}"
echo ""

# Load nccmp
if ! command -v nccmp &> /dev/null; then
    echo "ERROR: nccmp not found. Please load module: module load nccmp"
    exit 1
fi

CMP="nccmp -dmfqS"

echo "Checking test results..."
echo ""

all_tests_passed=0
total_tests=0
passed_tests=0

# Test 01: Snow DA LETKF GHCN
TEST_NAME="snowDA_letkf_ghcn"
TEST_OUTDIR=${DATA}/testcase_${TEST_NAME}
BASELINE_DIR=${HOMEreg}/baseline_data/snowDA_letkf_ghcn

total_tests=$((total_tests + 1))
echo "========== Test $total_tests: ${TEST_NAME} =========="
echo ""

if [[ ! -d "${TEST_OUTDIR}/mem000/restarts/vector" ]]; then
    echo "ERROR: Test output directory not found: ${TEST_OUTDIR}/mem000/restarts/vector"
    echo "Test may still be running. Check job status with: squeue -u ${USER}"
    echo ""
    continue
fi

if [[ ! -d "${BASELINE_DIR}" ]]; then
    echo "ERROR: Baseline directory not found: ${BASELINE_DIR}"
    echo "Run with UPDATE_BASELINE=TRUE to create initial baseline."
    echo ""
    continue
fi

test_passed=0

# Check analysis files
echo "Analysis files:"
for anal_file in ${TEST_OUTDIR}/mem000/restarts/vector/*anal*.nc
do
    if [[ -f "${anal_file}" ]]; then
        filename=$(basename "${anal_file}")
        baseline_file="${BASELINE_DIR}/${filename}"
        
        if [[ -f "${baseline_file}" ]]; then
            echo -n "  ${filename}... "
            $CMP "${anal_file}" "${baseline_file}" > /dev/null 2>&1
            cmp_iret=$?
            
            if [[ $cmp_iret -eq 0 ]]; then
                echo "PASS"
                passed_tests=$((passed_tests + 1))
                test_passed=1
            else
                echo "FAIL (output differs from baseline)"
                echo "    Expected: ${baseline_file}"
                echo "    Got:      ${anal_file}"
                test_passed=0
            fi
        else
            echo "  WARNING: No baseline for ${filename}"
            echo "    Create baseline with: cp ${anal_file} ${baseline_file}"
        fi
    fi
done

echo ""

if [[ $test_passed -eq 1 ]]; then
    echo "Test Result: PASSED"
else
    echo "Test Result: FAILED or INCOMPLETE"
    all_tests_passed=1
fi

echo ""

echo "========================================"
echo "Summary"
echo "========================================"
echo "Total tests: ${total_tests}"
echo "Passed tests: ${passed_tests}"
echo ""

if [[ $all_tests_passed -eq 0 ]] && [[ $passed_tests -eq $total_tests ]]; then
    echo "<<< ALL SNOW DA TESTS PASSED >>>"
    exit 0
else
    echo "<<< SOME SNOW DA TESTS FAILED or INCOMPLETE >>>"
    exit 1
fi
