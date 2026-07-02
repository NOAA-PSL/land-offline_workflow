#!/bin/bash

module load nccmp

CMP="nccmp -d"

# Ensure OUTDIR is defined (fallback to current directory if empty, or throw an error)
if [[ -z "${OUTDIR}" ]]; then
    echo "ERROR: OUTDIR environment variable is not set."
    exit 1
fi

dir_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GDASApp_root=${dir_root}/../DA_update/GDASApp/
source $GDASApp_root/ush/detect_machine.sh

if [[ ${MACHINE_ID} == 'ursa' ]]; then
    echo "checking reg_tests on URSA"
    TEST_BASE_ROOT="/scratch4/NCEPDEV/land/data/DA/offline_workflow/baseline/ens20_ghcn_letkf"
elif [[ ${MACHINE_ID} == 'gaeac6' ]]; then
    echo "checking reg_tests on GAEA C6"
    TEST_BASE_ROOT="/gpfs/f6/land-cpu/world-shared/Yuan.Xue/offline_workflow/baseline/ens20_ghcn_letkf"
else
    echo "reg_tests currently supported only on URSA and GAEA C6"
    exit 1
fi

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
