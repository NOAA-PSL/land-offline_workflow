#!/bin/sh 

# get OUTDIR
source settings_cycle_test

#CMP='/scratch1/NCEPDEV/global/spack-stack/spack-stack-v1/envs/skylab-3.0.0-intel-2021.5.0/install/intel/2021.5.0/nccmp-1.9.0.1-jtyxxm5/bin/nccmp -d'
CMP = 'cmp'

TEST_BASEDIR=/scratch2/BMC/gsienkf/Clara.Draper/DA_test_cases/land-offline_workflow/DA_IMS_test_20230509/output/mem000/restarts/vector/

for TEST_DATE in 2019-10-01_18-00-00 2019-10-02_18-00-00 
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

TEST_DATE=2019-10-03_18-00-00
state='back'
$CMP ${OUTDIR}/mem000/restarts/vector/ufs_land_restart_${state}.${TEST_DATE}.nc ${TEST_BASEDIR}/ufs_land_restart_${state}.${TEST_DATE}.nc

if [[ $? != 0 ]]; then
    echo TEST FAILED
    echo "$TEST_DATE $state are different"
    exit
fi

echo "TEST PASSED"

exit
