#!/bin/bash
set -e
################################################
# pass arguments
project_binary_dir=$1
project_source_dir=$2

# Export runtime env. variables
source ${project_source_dir}/test/runtime_vars.sh ${project_binary_dir} ${project_source_dir}

# set extra paths
OBSDIR=$LANDDA_TESTDATA/DA/snow_ice_cover
RSTDIR=$project_binary_dir/test/bkg/restarts/tile

# set executables
TEST_EXEC="calcfIMS.exe"
NPROC=1

# set IODA converter
IODA_EXEC=$project_source_dir/DA_update/jedi/ioda/imsfv3_scf2ioda_obs40.py #${EXECDIR}/imsfv3_scf2ioda.p

# move to work directory
cd $WORKDIR

# Clean test files created during a previous test
[[ -e ./ioda/ioda.IMSscf.${YY}${MM}${DD}.${TSTUB}.nc ]] && rm ./ioda/ioda.IMSscf.${YY}${MM}${DD}.${TSTUB}.nc
[[ ! -e ./ioda ]] && mkdir -p ./ioda
[[ -e fims.nml ]] && rm fims.nml
[[ -e IMSscf.${YY}${MM}${DD}.${TSTUB}.nc ]] && rm IMSscf.${YY}${MM}${DD}.${TSTUB}.nc
for i in ./${FILEDATE}.sfc_data.tile*.nc;
do
  [[ -e $i ]] && rm $i
done

# set namelist
cat >> fims.nml << EOF
 &fIMS_nml
  idim=$RES, jdim=$RES,
  otype=${TSTUB},
  jdate=$YY$DOY,
  yyyymmddhh=$YY$MM$DD.18,
  imsformat=2,
  imsversion=1.3,
  IMS_OBS_PATH="${OBSDIR}/IMS/$YY/",
  IMS_IND_PATH="${OBSDIR}/IMS/index_files/"
  /
EOF

# stage restarts
for i in ${RSTDIR}/${FILEDATE}.sfc_data.tile*.nc;
do
  ln -fs $i .
done

ulimit -Ss unlimited
echo "============================= calling ${TEST_EXEC}"
$MPIRUN -n ${NPROC} ${EXECDIR}/${TEST_EXEC}

echo "============================= calling ioda converter"
$MPIRUN -n ${NPROC} $PYTHON_EXEC ${IODA_EXEC} -i IMSscf.${YY}${MM}${DD}.${TSTUB}.nc -o ./ioda/ioda.IMSscf.${YY}${MM}${DD}.${TSTUB}.nc
