#!/bin/bash

module load nccmp

CMP="nccmp -d"

# Ensure OUTDIR is defined (fallback to current directory if empty, or throw an error)
if [[ -z "${OUTDIR}" ]]; then
    echo "ERROR: OUTDIR environment variable is not set."
    exit 1
fi

# Base directory for the baseline datasets
TEST_BASE_ROOT="/scratch4/NCEPDEV/land/data/DA/offline_workflow/baseline/ens20_ghcn_letkf"

# Loop through members 001 to 020 using Bash brace expansion
for i in {001..020}
do
    MEMBER="mem${i}"
    echo "--------------------------------------------"
    echo "Checking dataset for: ${MEMBER}"
    echo "--------------------------------------------"

    for TEST_DATE in 2024-03-01_00-00-00 2024-03-02_00-00-00 
    do
        for state in back anal 
        do 
            # Construct the dynamic file paths
            FILE_OUT="${OUTDIR}/${MEMBER}/vector/ufs_land_restart_${state}.${TEST_DATE}.nc"
            FILE_REF="${TEST_BASE_ROOT}/${MEMBER}/vector/ufs_land_restart_${state}.${TEST_DATE}.nc"

            # Check if files actually exist before running nccmp to prevent false positives/negatives
            if [[ ! -f "$FILE_OUT" || ! -f "$FILE_REF" ]]; then
                echo "TEST FAILED: One or both files missing for ${MEMBER} (${TEST_DATE} - ${state})"
                exit 1
            fi

            # Run the comparison
            $CMP "$FILE_OUT" "$FILE_REF"

            if [[ $? -ne 0 ]]; then
                echo "TEST FAILED"
                echo "${MEMBER} -> ${TEST_DATE} ${state} are different"
                exit 1
            else 
                echo "${MEMBER} -> ${TEST_DATE} ${state} OK"
            fi
        done
    done
done 

echo "========================================"
echo "GHCN LETKF SNOWDA TEST PASSED FOR ALL MEMS"
echo "========================================"

exit 0
