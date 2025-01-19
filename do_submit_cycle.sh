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

echo "reading cycle settings from $config_file"
source $config_file

export KEEPWORKDIR="YES"

CYCLEDIR=${CYCLEDIR:-$(pwd)} 

############################
# set executables
export apps_dir=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/APPS/
export apps_bin=$apps_dir/bin
export vector2tile_exe=$apps_dir/vector2tile/vector2tile_converter.exe
# export vec2tileexec=${CYCLEDIR}/vector2tile/vector2tile_converter.exe
export LSMexec=${CYCLEDIR}/ufs-land-driver/run/ufsLand.exe
export EnsGenExe=${CYCLEDIR}/stochastic_physics/EnsGen.x

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

# Jan 11.2025: Changes to accomodate hyb2DenVar
# - mem000: for ensemble mean when applicable
# - memdet: for deterministic 'members' of 2DVar, letkf-oi, hyb2DenVar 

mem_ens="memdet"  # deterministic DA cases (2DVar/letkf-oi/the 2DVar part of hyb2DEnVar) 
MEM_WORKDIR=${WORKDIR}/${mem_ens}
mkdir $MEM_WORKDIR

#outdir for model
if [[ ! -e ${OUTDIR} ]]; then    

    mkdir -p  ${OUTDIR}

    # ensemble outdir (model only)
    MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}    
    if [[ ! -e $MEM_MODL_OUTDIR ]]; then  
        mkdir -p $MEM_MODL_OUTDIR
    fi

    # outdir subdirs
    if [[ ! -e ${MEM_MODL_OUTDIR}/restarts/ ]]; then  
        mkdir -p ${MEM_MODL_OUTDIR}/restarts/
        mkdir -p ${MEM_MODL_OUTDIR}/restarts/vector/ 
        mkdir ${MEM_MODL_OUTDIR}/restarts/tile/
    fi

    mkdir -p ${MEM_MODL_OUTDIR}/noahmp/
    ln -sf ${MEM_MODL_OUTDIR}/noahmp ${MEM_WORKDIR}/noahmp_output 

    # stochy: ensemble forcing perturbation
    if [[ ! -e ${OUTDIR}/STOCHY/ ]]; then  
        mkdir -p ${OUTDIR}/STOCHY/        
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
        fi

        # outdir subdirs
        if [[ ! -e ${MEM_MODL_OUTDIR}/restarts/ ]]; then  
            mkdir -p ${MEM_MODL_OUTDIR}/restarts/
            mkdir -p ${MEM_MODL_OUTDIR}/restarts/vector/ 
            mkdir ${MEM_MODL_OUTDIR}/restarts/tile/            
        fi

        #TODO: Do we need this?
        mkdir -p ${MEM_MODL_OUTDIR}/noahmp/
        ln -sf ${MEM_MODL_OUTDIR}/noahmp ${MEM_WORKDIR}/noahmp_output 
    done 
fi

# Forcing perturbation 
# Make sure the INPUT and RESTART dirs for stochy are in working dir
# and input.nml has settings right
if [[ $do_enkf == "YES" ]]; then     
    
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
        if [[ -e ${grid_file} ]]; then
           ln -fs ${grid_file}  ${WORKDIR}/INPUT/C${RES}_grid.tile7.nc 
        else
            for it in $(seq 1 $num_tiles) 
            do
                ln -fs ${TPATH}/C${RES}_grid.tile${it}.nc  ${WORKDIR}/INPUT/C${RES}_grid.tile${it}.nc 
                # ln -fs ${TPATH}/C${RES}_ca_condition.tile${it}.nc  ${WORKDIR}/INPUT/C${RES}_ca_condition.tile${it}.nc 
            done
        fi

        if [[ -e ${grid_spec} ]]; then
           ln -fs ${grid_spec}  ${WORKDIR}/INPUT/C${RES}_grid_spec.nc
        else
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
fi

# copy ICS into restarts, if needed 
mem_ens="memdet"  # single member/deterministic 
rst_out=${OUTDIR}/${mem_ens}/restarts/vector/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
rst_in=${ICSDIR}/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
# if restart not in experiment out directory, copy the restarts from the ICSDIR
if [[ ! -e ${rst_out} ]]; then 
    echo "Looking for ICS: ${rst_in}"
    if [[ -e "${rst_in}" ]]; then
        echo "ICS found, copying" 
        cp ${rst_in} ${rst_out}
    else  # check if is in output directory structure
        rst_in=${ICSDIR}/${mem_ens}/restarts/vector/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
        echo "Looking for ICS: ${rst_in}"
        if [[ -e ${rst_in} ]]; then
            echo "ICS found, copying" 
            cp ${rst_in} ${rst_out}
        else  
            echo "ICS not found. Exiting" 
            exit 10 
        fi
    fi 
else
    echo "ICs exist in out dir: ${rst_out}"
fi 

if [[ "$ensemble_size" -gt 1  ]]; then  
    
    for ie in $(seq 0 $ensemble_size)     
    do
        mem_ens="mem`printf %03i $ie`"
        rst_out=${OUTDIR}/${mem_ens}/restarts/vector/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
        # if restart not in experiment out directory, copy the restarts from the ICSDIR
        if [[ ! -e ${rst_out} ]]; then 
            # for ensembles, first check individual IC directory structure
            rst_in=${ICSDIR}/${mem_ens}/restarts/vector/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
            echo "Looking for ICS: ${rst_in}"
            if [[ -e ${rst_in} ]]; then
                echo "ICS found, copying" 
                cp ${rst_in} ${rst_out}
            else  # if individual ens ember IC doesn't exit, copy same IC for all ens members, if available
                rst_in=${ICSDIR}/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
                echo "Looking for ICS: ${rst_in}"
                if [[ -e ${rst_in} ]]; then
                    echo "ICS found, copying" 
                    cp ${rst_in} ${rst_out}
                else  
                    echo "ICS not found. Exiting." 
                    exit 10 
                fi
            fi 
        else
            echo "ICs exist in out dir: ${rst_out}"
        fi 
    done
fi

#---------------
# create dates file 
touch analdates.sh 
cat << EOF > analdates.sh
STARTDATE=$STARTDATE
ENDDATE=$ENDDATE
EOF

# submit script 
sbatch submit_cycle.sh
