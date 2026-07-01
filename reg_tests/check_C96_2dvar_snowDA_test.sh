#!/bin/bash

module load nccmp

CMP="nccmp -d"

# Ensure OUTDIR is defined (prevents evaluating blank relative paths)
if [[ -z "${OUTDIR}" ]]; then
    echo "ERROR: OUTDIR environment variable is not set."
    exit 1
fi

dir_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GDASApp_root=${dir_root}/../DA_update/GDASApp/
source $GDASApp_root/ush/detect_machine.sh

if [[ ${MACHINE_ID} == 'ursa' ]]; then
    echo "checking reg_tests on URSA"
    TEST_BASEDIR="/scratch4/NCEPDEV/land/data/DA/offline_workflow/baseline/ims_2dvar/vector"
elif [[ ${MACHINE_ID} == 'gaeac6' ]]; then
    echo "checking reg_tests on GAEA C6"
    TEST_BASEDIR="/gpfs/f6/land-cpu/world-shared/Yuan.Xue/offline_workflow/baseline/ims_2dvar/vector"
else
    echo "reg_tests currently supported only on URSA and GAEA C6"
    exit 1
fi
    
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
