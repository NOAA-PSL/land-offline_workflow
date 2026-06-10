#!/bin/bash

#------------------------------------------------------------------
# Snow DA Regression Test: C384 LETKF with GHCN observations
#
# This test performs:
#   1. Snow DA with LETKF algorithm
#   2. GHCN observation assimilation
#   3. Output validation against baseline
#
# Follows UFS_UTILS pattern: environment setup, execution, validation
#------------------------------------------------------------------

set -x

NCCMP=${NCCMP:-$(which nccmp)}

echo "========================================"
echo "C384 Snow DA LETKF GHCN Test"
echo "========================================"

# Get directories
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "${SCRIPT_DIR}/../../" && pwd )"
RT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

echo "Script dir: ${SCRIPT_DIR}"
echo "Root dir: ${ROOT_DIR}"
echo "RT dir: ${RT_DIR}"
echo ""

# Source rt.control for baseline directory
if [[ -f "${RT_DIR}/rt.control" ]]; then
    source ${RT_DIR}/rt.control
    echo "Sourced rt.control"
else
    echo "ERROR: Cannot find rt.control at ${RT_DIR}/rt.control"
    exit 1
fi

# Source snow DA test settings
if [[ -f "${ROOT_DIR}/settings_snowDA_test_workflow" ]]; then
    source ${ROOT_DIR}/settings_snowDA_test_workflow
    echo "Sourced settings_snowDA_test_workflow"
else
    echo "ERROR: Cannot find settings_snowDA_test_workflow at ${ROOT_DIR}/settings_snowDA_test_workflow"
    exit 1
fi

# Override for this specific test case
export CASE="C384"
export RES=384
export DAalg="letkf"
export OBS_TYPES=("GHCN")
export JEDI_TYPES=("DA")

echo "Test configuration:"
echo "  Case: ${CASE}"
echo "  Resolution: C${RES}"
echo "  DA Algorithm: ${DAalg}"
echo "  Observations: ${OBS_TYPES[@]}"
echo "  Start date: ${STARTDATE}"
echo "  End date: ${ENDDATE}"
echo ""

# Set test-specific directories
TEST_NAME="snowDA_letkf_ghcn"
TEST_OUTDIR=${DATA}/testcase_${TEST_NAME}
TEST_WORKDIR=${DATA}/workdir_${TEST_NAME}

echo "Output directory: ${TEST_OUTDIR}"
echo "Work directory: ${TEST_WORKDIR}"
echo ""

# Clean and create directories
if [[ -d ${TEST_OUTDIR} ]]; then
    rm -rf ${TEST_OUTDIR}
fi
mkdir -p ${TEST_OUTDIR}/mem000/restarts/vector
mkdir -p ${TEST_OUTDIR}/DA/hofx
mkdir -p ${TEST_OUTDIR}/DA/jedi_conf

if [[ -d ${TEST_WORKDIR} ]]; then
    rm -rf ${TEST_WORKDIR}
fi
mkdir -p ${TEST_WORKDIR}

# Temporary override of OUTDIR and WORKDIR for this test
export OUTDIR=${TEST_OUTDIR}
export WORKDIR=${TEST_WORKDIR}

echo "Running snow DA test workflow..."
echo ""

# Call do_submit_cycle.sh with snow DA settings
cd ${ROOT_DIR}

# Check if do_submit_cycle.sh exists
if [[ ! -f "./do_submit_cycle.sh" ]]; then
    echo "ERROR: Cannot find do_submit_cycle.sh in ${ROOT_DIR}"
    exit 1
fi

echo "Executing: ./do_submit_cycle.sh settings_snowDA_test_workflow"
./do_submit_cycle.sh settings_snowDA_test_workflow
iret=$?

if [[ $iret -ne 0 ]]; then
    echo ""
    echo "<<< SNOW DA TEST FAILED - do_submit_cycle.sh failed >>>"
    exit $iret
fi

echo ""
echo "Snow DA workflow completed successfully."
echo "Validating output files..."
echo ""

# Validation using nccmp (similar to check_snowDA_test.sh)
test_failed=0

# Check for required nccmp
if ! command -v nccmp &> /dev/null; then
    echo "WARNING: nccmp not available. Checking file existence only."
    nccmp_available=0
else
    nccmp_available=1
fi

# Define baseline directory
BASELINE_DIR=${HOMEreg}/baseline_data/snowDA_letkf_ghcn

echo "Baseline directory: ${BASELINE_DIR}"
echo ""

# Check analysis files exist
if [[ -d "${TEST_OUTDIR}/mem000/restarts/vector" ]]; then
    echo "Checking analysis files..."
    
    for anal_file in ${TEST_OUTDIR}/mem000/restarts/vector/*anal*.nc
    do
        if [[ -f "${anal_file}" ]]; then
            filename=$(basename "${anal_file}")
            echo -n "Checking ${filename}... "
            
            # Check if baseline exists
            if [[ -f "${BASELINE_DIR}/${filename}" ]]; then
                if [[ $nccmp_available -eq 1 ]]; then
                    # Compare with baseline using nccmp
                    $NCCMP -dmfqS "${anal_file}" "${BASELINE_DIR}/${filename}" > /dev/null 2>&1
                    cmp_iret=$?
                    
                    if [[ $cmp_iret -eq 0 ]]; then
                        echo "OK (matches baseline)"
                    else
                        echo "DIFF (differs from baseline)"
                        test_failed=1
                        # Show summary of differences
                        echo "  Running detailed comparison:"
                        $NCCMP -dmfqS "${anal_file}" "${BASELINE_DIR}/${filename}" | head -20
                    fi
                else
                    echo "OK (file exists, baseline exists, nccmp unavailable)"
                fi
            else
                echo "OK (file exists, baseline not found - will be created if UPDATE_BASELINE=TRUE)"
            fi
        fi
    done
    
    # Also check background files if they exist
    echo ""
    echo "Checking background files..."
    
    for back_file in ${TEST_OUTDIR}/mem000/restarts/vector/*back*.nc
    do
        if [[ -f "${back_file}" ]]; then
            filename=$(basename "${back_file}")
            echo -n "Checking ${filename}... "
            
            if [[ -f "${BASELINE_DIR}/${filename}" ]]; then
                if [[ $nccmp_available -eq 1 ]]; then
                    $NCCMP -dmfqS "${back_file}" "${BASELINE_DIR}/${filename}" > /dev/null 2>&1
                    cmp_iret=$?
                    
                    if [[ $cmp_iret -eq 0 ]]; then
                        echo "OK (matches baseline)"
                    else
                        echo "DIFF (differs from baseline)"
                        test_failed=1
                    fi
                else
                    echo "OK (file exists, baseline exists)"
                fi
            else
                echo "OK (file exists, baseline not found)"
            fi
        fi
    done
else
    echo "ERROR: Analysis directory not found: ${TEST_OUTDIR}/mem000/restarts/vector"
    test_failed=1
fi

echo ""
echo "========================================"

if [[ $test_failed -ne 0 ]]; then
    echo "<<< SNOW DA LETKF GHCN TEST FAILED >>>"
    echo ""
    echo "Differences detected in output files."
    
    if [[ "${UPDATE_BASELINE}" == "TRUE" ]]; then
        echo ""
        echo "Updating baseline data..."
        mkdir -p ${BASELINE_DIR}
        cp ${TEST_OUTDIR}/mem000/restarts/vector/*.nc ${BASELINE_DIR}/
        echo "Baseline updated at: ${BASELINE_DIR}"
    fi
    
    exit 1
else
    echo "<<< SNOW DA LETKF GHCN TEST PASSED >>>"
    echo ""
    echo "All validation checks passed."
    exit 0
fi
