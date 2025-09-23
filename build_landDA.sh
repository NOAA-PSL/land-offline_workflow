#!/bin/bash
driver_git='https://github.com/NOAA-PSL/land-offline_workflow.git'
flag_dl_workflow='YES'
flag_dl_gdasapp='YES'
#************************************
#if set flag_dl_gdasapp to 'NO', please specify 
#GDASApp_path in DA_update/make_links.sh
#************************************
echo '********************************'
iargs=$#
script=$0
if [ ! $iargs = 2 ] ; then
  echo 'Usage: '$script' target_dir_name machine[ursa|hera]'
  exit
else
  directory=$1
  machine=$2
  echo ' Command: '$script' '$directory' '$machine
fi
echo '--------------------------------'
new_dir=$directory/land-offline_workflow
echo "Prepare the directory "$new_dir
if [ $flag_dl_workflow = 'YES' ]; then
  rm -rf $new_dir
  mkdir -p $new_dir
echo '--------------------------------'
echo "Clone the repo"
  cd $directory
  git clone -b develop --recurse-submodules $driver_git
fi
if [ $flag_dl_gdasapp = 'YES' ]; then
  cd $new_dir/DA_update
  git clone --recursive https://github.com/NOAA-EMC/gdasapp.git GDASApp
  cd $new_dir/DA_update/GDASApp
  ./build.sh -f -v >& build_log.log&
fi
echo '--------------------------------'
echo "load modules"
if [ $machine = 'ursa' ]; then
cat > $new_dir/land_mods << EOF1
module purge
module use /contrib/spack-stack/spack-stack-1.9.2/envs/ue-oneapi-2024.2.1/install/modulefiles/Core
module load stack-oneapi/2024.2.1 stack-intel-oneapi-mpi/2021.13 netcdf-fortran/4.6.1
EOF1
fi
source $new_dir/land_mods
echo '--------------------------------'
echo "compile ufs-land-driver"
cd $new_dir/ufs-land-driver
if [ $machine = 'ursa' ]; then
  echo 1 | ./configure # 1=ursa-parallel
elif [ $machine = 'hera' ]; then
  echo 2 | ./configure # 2=hera-parallel
fi
make
echo '--------------------------------'
echo "compile vector2tile"
cd $new_dir/vector2tile
make
echo '--------------------------------'
echo "compile DA_update"
cd $new_dir/DA_update
#if set flag_dl_gdasapp to 'NO', please modify make_links.sh
./make_links.sh
./build_all.sh
