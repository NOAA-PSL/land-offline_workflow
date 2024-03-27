#!/bin/bash

# get OUTDIR
source settings_cycle_test

# need to run "module load nccmp" before calling

module load nccmp

CMP="nccmp -d"

TEST_BASEDIR=/scratch2/BMC/gsienkf/Clara.Draper/DA_test_cases/land-offline_workflow/DA_test_era5/mem000/restarts/vector/

for TEST_DATE in 2019-12-21_00-00-00 2019-12-22_00-00-00 
do

for state in  back anal 
do 

$CMP ${OUTDIR}/mem000/restarts/vector/ufs_land_restart_${state}.${TEST_DATE}.nc ${TEST_BASEDIR}/ufs_land_restart_${state}.${TEST_DATE}.nc

if [[ $? != 0 ]]; then
    echo TEST FAILED
    echo "$TEST_DATE $state are different"
    exit
else 
    echo "$TEST_DATE $state OK"
fi

done
done 

TEST_DATE=2019-12-23_00-00-00
state='back'
$CMP ${OUTDIR}/mem000/restarts/vector/ufs_land_restart_${state}.${TEST_DATE}.nc ${TEST_BASEDIR}/ufs_land_restart_${state}.${TEST_DATE}.nc

if [[ $? != 0 ]]; then
    echo TEST FAILED
    echo "$TEST_DATE $state are different"
    exit
fi

echo "TEST PASSED"

exit
