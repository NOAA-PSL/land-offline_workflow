#!/bin/bash

# get OUTDIR
source settings_cycle_test

# need to run "module load nccmp" before calling

module load nccmp

CMP="nccmp -d"

TEST_BASEDIR=/scratch4/NCEPDEV/land/data/DA/offline_workflow/snowDA_test_era5/mem000/restarts/vector/

for TEST_DATE in 2021-12-01_00-00-00 2021-12-02_00-00-00 
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

TEST_DATE=2021-12-03_00-00-00
state='back'
$CMP ${OUTDIR}/mem000/restarts/vector/ufs_land_restart_${state}.${TEST_DATE}.nc ${TEST_BASEDIR}/ufs_land_restart_${state}.${TEST_DATE}.nc

if [[ $? != 0 ]]; then
    echo TEST FAILED
    echo "$TEST_DATE $state are different"
    exit
fi

echo "SNOWDA TEST PASSED"

exit
