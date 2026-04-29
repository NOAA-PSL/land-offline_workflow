#!/bin/bash 

############################
# load config file 

if [[ $# -gt 0 ]]; then 
    config_file=$1
else
    config_file=settings
fi

if [[ ! -e $config_file ]]; then
    echo 'Config file does not exist. Exiting. '
    echo $config_file 
    exit 
fi

dir_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GDASApp_root=${dir_root}/DA_update/GDASApp/
source $GDASApp_root/ush/detect_machine.sh

if [[ ${MACHINE_ID} == 'ursa' ]]; then
    echo "running land offline workflow on URSA"
    export DATADIR=/scratch4/NCEPDEV/land/data/         
    export landmods=land_mods_ursa
    export stochymods=stochy_mods_ursa
elif [[ ${MACHINE_ID} == 'gaeac6' ]]; then
    echo "running land offline workflow on GAEA C6"
    export DATADIR=/gpfs/f6/land-cpu/proj-shared/DATA/   
    export landmods=land_mods_gaeac6
    export stochymods=stochy_mods_gaeac6
else
    echo "Land offline workflow currently supported only on URSA and GAEA C6"
    exit 1
fi
 
echo "reading cycle settings from $config_file"
source $config_file

export KEEPWORKDIR="YES"

export CYCLEDIR=${CYCLEDIR:-$(pwd)} 

############################
# set executables

export vec2tileexec=${CYCLEDIR}/vector2tile/vector2tile_converter.exe
export LSMexec=${CYCLEDIR}/ufs-land-driver/run/ufsLand.exe
export EnsGenExe=${CYCLEDIR}/land_ensemble_gen/EnsGen.x

export DADIR=${CYCLEDIR}/DA_update/
export DAscript=${DADIR}/do_landDA.sh

export analdate=${CYCLEDIR}/analdates.sh
export incdate=${CYCLEDIR}/incdate.sh

############################
# read in dates  

export logfile=${CYCLEDIR}/cycle.log
touch $logfile
echo "***************************************" >> $logfile
echo "cycling from $STARTDATE to $ENDDATE" >> $logfile

sYYYY=`echo $STARTDATE | cut -c1-4`
sMM=`echo $STARTDATE | cut -c5-6`
sDD=`echo $STARTDATE | cut -c7-8`
sHH=`echo $STARTDATE | cut -c9-10`

# compute the restart frequency, run_days and run_hours
export FREQ=$(( 3600 * $FCSTHR )) 
export RDD=$(( $FCSTHR / 24 )) 
export RHH=$(( $FCSTHR % 24 )) 

#############################
# set up directories

#workdir
if [[ -e ${WORKDIR} ]]; then 
    rm -rf ${WORKDIR}
fi
mkdir ${WORKDIR}

###############################
# create dirs and copy in ICS if needed

#outdir for model
if [[ ! -e ${OUTDIR} ]]; then    

    mkdir -p  ${OUTDIR}

    # outdir subdirs
    mkdir ${OUTDIR}/vector/
    mkdir ${OUTDIR}/tile/
    mkdir ${OUTDIR}/noahmp/
    ln -sf ${OUTDIR}/noahmp ${WORKDIR}/noahmp_output 
    
    # stochy: ensemble forcing perturbation
    if [[ ! -e ${OUTDIR}/STOCHY/ ]]; then  
        mkdir ${OUTDIR}/STOCHY/        
        mkdir ${OUTDIR}/STOCHY/RESTART/
        # mkdir ${OUTDIR}/STOCHY/INPUT/
    fi
fi

if [[ "$ensemble_size" -gt 1  ]]; then  

    for ie in $(seq 0 $ensemble_size)     
    do
        mem_ens="mem`printf %03i $ie`"        
        MEM_WORKDIR=${WORKDIR}/${mem_ens}
        mkdir $MEM_WORKDIR

        MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}
        if [[ ! -e $MEM_MODL_OUTDIR ]]; then  #ensemble outdir 
            mkdir -p $MEM_MODL_OUTDIR
            mkdir ${MEM_MODL_OUTDIR}/vector/ 
            mkdir ${MEM_MODL_OUTDIR}/tile/            
            #TODO: Do we need this?
	    mkdir -p ${MEM_MODL_OUTDIR}/noahmp/
            ln -sf ${MEM_MODL_OUTDIR}/noahmp ${MEM_WORKDIR}/noahmp_output
        fi 
    done 
fi

# Forcing perturbation 
# Make sure the INPUT and RESTART dirs for stochy are in working dir
# and input.nml has settings right
if [[ $do_enkf == "YES" ]]; then     
    
    export TPATH=${FIXorog}/C${RES}	
    export stochy_init_found="NO"
    
    if [[ $stochy_init_exist == "YES" ]]; then

        if [[ -e ${stochy_init_dir} ]]; then
	        echo "Stochy init files found. Copying..."
            cp ${stochy_init_dir}/*.nc ${OUTDIR}/STOCHY/RESTART/ 
            export stochy_init_found="YES"     	    
        else
            echo "directory for Stochy init files $stochy_init_dir doesn't exist."
            echo "STOCH_INI_VAL will be set to FALSE "
        fi
    else
        echo "STOCH_INI_VAL will be set to FALSE "
    fi

    ln -fs ${OUTDIR}/STOCHY/RESTART/ ${WORKDIR}/RESTART  

    if [[ ! -e ${WORKDIR}/INPUT ]]; then
        mkdir -p ${WORKDIR}/INPUT
        for it in $(seq 1 $num_tiles) 
        do
            ln -fs ${TPATH}/C${RES}_grid.tile${it}.nc  ${WORKDIR}/INPUT/C${RES}_grid.tile${it}.nc 
            # ln -fs ${TPATH}/C${RES}_ca_condition.tile${it}.nc  ${WORKDIR}/INPUT/C${RES}_ca_condition.tile${it}.nc 
        done
        if [[ -e ${TPATH}/C${RES}_grid_spec.nc ]]; then
            ln -fs ${TPATH}/C${RES}_grid_spec.nc  ${WORKDIR}/INPUT/C${RES}_grid_spec.nc   
        elif [[ -e ${TPATH}/C${RES}_mosaic.nc ]]; then
            ln -fs ${TPATH}/C${RES}_mosaic.nc  ${WORKDIR}/INPUT/C${RES}_grid_spec.nc  
        else
            echo "Grid spec file not found at ${TPATH}, exiting"
            exit 10
        fi          
    fi 
fi

# copy ICS if needed
# update 2.17.26: also copy restarts to working dir to skip "do_jedi" section for openloop runs
# update 4.8.26: use outdir/workdir for deterministic; reserve mem000 for ens mean
rst_out=${OUTDIR}/vector/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
rst_in=${ICSDIR}/vector/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
# if restart not in experiment out directory, copy the restarts from the ICSDIR
if [[ ! -e ${rst_out} ]]; then 
    echo "Looking for ICS: ${rst_in}"
    if [[ -e "${rst_in}" ]]; then
       echo "ICS found, copying" 
       cp ${rst_in} ${rst_out}
       cp ${rst_in} ${WORKDIR}/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
    else  
       echo "ICS not found. Exiting" 
       exit 10 
    fi 
fi 

if [[ "$ensemble_size" -gt 1  ]]; then  

    for ie in $(seq $ensemble_size)     
    do
        mem_ens="mem`printf %03i $ie`"
        rst_out=${OUTDIR}/${mem_ens}/vector/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
        rst_in=${ICSDIR}/${mem_ens}/vector/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
	MEM_WORKDIR=${WORKDIR}/${mem_ens}
        # if restart not in experiment out directory, copy the restarts from the ICSDIR
        if [[ ! -e ${rst_out} ]]; then 
            echo "Looking for ICS: ${rst_in}"
            if [[ -e ${rst_in} ]]; then
                echo "ICS found, copying" 
                cp ${rst_in} ${rst_out}
                cp ${rst_in} ${MEM_WORKDIR}/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
            else  
                echo "ICS not found. Exiting" 
                exit 10 
            fi 
        fi 
    done
fi

# run using baseline snow parameter table
# copy once into workdir
cp ${CYCLEDIR}/ufs-land-driver/ccpp-physics/physics/SFC_Models/Land/Noahmp/noahmptable.tbl $WORKDIR/noahmptable.tbl

#---------------
# create dates file 
touch analdates.sh 
cat << EOF > analdates.sh
STARTDATE=$STARTDATE
ENDDATE=$ENDDATE
EOF

# submit script 
sbatch submit_cycle.sh
