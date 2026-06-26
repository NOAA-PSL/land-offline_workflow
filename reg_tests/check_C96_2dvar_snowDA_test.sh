#!/bin/bash

module load nccmp

CMP="nccmp -d"

# Ensure OUTDIR is defined (prevents evaluating blank relative paths)
if [[ -z "${OUTDIR}" ]]; then
    echo "ERROR: OUTDIR environment variable is not set."
    exit 1
fi

TEST_BASEDIR="/scratch4/NCEPDEV/land/data/DA/offline_workflow/baseline/ims_2dvar/vector"

for TEST_DATE in 2024-03-01_00-00-00 2024-03-02_00-00-00 
do
    for state in back anal 
    do 
        # Construct clean file paths
        FILE_OUT="${OUTDIR}/vector/ufs_land_restart_${state}.${TEST_DATE}.nc"
        FILE_REF="${TEST_BASEDIR}/ufs_land_restart_${state}.${TEST_DATE}.nc"

        # Check if files exist before running nccmp to capture outright missing outputs cleanly
        if [[ ! -f "$FILE_OUT" || ! -f "$FILE_REF" ]]; then
            echo "TEST FAILED: One or both files missing (${TEST_DATE} - ${state})"
            echo "  Generated: $FILE_OUT"
            echo "  Reference: $FILE_REF"
            exit 1
        fi

        # Run the comparison
        $CMP "$FILE_OUT" "$FILE_REF"

        if [[ $? -ne 0 ]]; then
            echo "TEST FAILED"
            echo "$TEST_DATE $state are different"
            exit 1
        else 
            echo "$TEST_DATE $state OK"
        fi
    done
done 

echo "========================================"
echo "IMS 2DVAR SNOWDA TEST PASSED"
echo "========================================"

exit 0
