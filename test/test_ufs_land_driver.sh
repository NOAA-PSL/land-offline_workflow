#!/bin/bash
set -e
################################################
# pass arguments
project_binary_dir=$1
project_source_dir=$2

# Export runtime env. variables
source ${project_source_dir}/test/runtime_vars.sh ${project_binary_dir} ${project_source_dir}

# compute the restart frequency, run_days and run_hours
FREQ=$(( 3600 * $FCSTHR ))
RDD=$(( $FCSTHR / 24 ))
RHH=$(( $FCSTHR % 24 ))

# set executables
TEST_EXEC="ufsLandDriver.exe"
NPROC=1

# move to work directory
cd $WORKDIR

# clean output folder
[[ -e noahmp_output ]] && rm -rf noahmp_output
[[ -e ufs-land.namelist ]] && rm ufs-land.namelist
for i in ./ufs_land_restart*.nc;
do
  [[ -e $i ]] && rm $i
done
mkdir -p ./noahmp_output

# update model namelist
cp  $project_source_dir/test/testinput/template.ufs-noahMP.namelist.${atmos_forc}  ufs-land.namelist
sed -i "s|LANDDA_TESTDATA|${LANDDA_TESTDATA}|g" ufs-land.namelist
sed -i -e "s/XXYYYY/${YY}/g" ufs-land.namelist
sed -i -e "s/XXMM/${MM}/g" ufs-land.namelist
sed -i -e "s/XXDD/${DD}/g" ufs-land.namelist
sed -i -e "s/XXHH/${HH}/g" ufs-land.namelist
sed -i -e "s/XXFREQ/${FREQ}/g" ufs-land.namelist
sed -i -e "s/XXRDD/${RDD}/g" ufs-land.namelist
sed -i -e "s/XXRHH/${RHH}/g" ufs-land.namelist

# link to resart file
ln -fs ${WORKDIR}/ana/restarts/vector/ufs_land_restart.${YY}-${MM}-${DD}_${HH}-00-00.nc .

# submit model
echo "============================= calling model" 
$MPIRUN -n $NPROC ${EXECDIR}/${TEST_EXEC} 
