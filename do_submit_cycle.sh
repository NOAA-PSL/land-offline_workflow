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

export CYCLEDIR=$(pwd) 

############################
# set executables

export vec2tileexec=${CYCLEDIR}/vector2tile/vector2tile_converter.exe
export LSMexec=${CYCLEDIR}/ufs-land-driver/run/ufsLand.exe
# export EnsForcGenExe=${CYCLEDIR}/stochastic_physics/GenEnsForc.x
export EnsForcGenExe=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/APPS/stochastic_physics_mod/GenEnsForc.x

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

############################
# set up directories

#workdir
if [[ -e ${WORKDIR} ]]; then 
    rm -rf ${WORKDIR}
fi
mkdir ${WORKDIR}

###############################
# create dirs and copy in ICS if needed
mem_ens="mem000"  # single member, us ensemble 0
MEM_WORKDIR=${WORKDIR}/${mem_ens}
# if [[ ! -e $MEM_WORKDIR ]];   # already deleted above
mkdir $MEM_WORKDIR

if [[ ! -e ${OUTDIR} ]]; then    

    mkdir -p  ${OUTDIR}
    MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}    
    if [[ ! -e $MEM_MODL_OUTDIR ]]; then  #ensemble outdir 
        mkdir -p $MEM_MODL_OUTDIR
    fi

    # outdir subdirs
    if [[ ! -e ${MEM_MODL_OUTDIR}/restarts/ ]]; then  # subdirectories
        mkdir -p ${MEM_MODL_OUTDIR}/restarts/
        mkdir -p ${MEM_MODL_OUTDIR}/restarts/vector/ 
        mkdir ${MEM_MODL_OUTDIR}/restarts/tile/
    fi
    #TODO: Do we need this?
    mkdir -p ${MEM_MODL_OUTDIR}/noahmp/
    ln -sf ${MEM_MODL_OUTDIR}/noahmp ${MEM_WORKDIR}/noahmp_output 

fi

if [[ "$ensemble_size" -gt 1  ]]; then  

    # ensemble outdir (model only)
    for ie in $(seq $ensemble_size)     
    do
        mem_ens="mem`printf %03i $ie`"
        
        MEM_WORKDIR=${WORKDIR}/${mem_ens}
        MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

        mkdir $MEM_WORKDIR
    
        if [[ ! -e $MEM_MODL_OUTDIR ]]; then  #ensemble outdir 
            mkdir -p $MEM_MODL_OUTDIR
        fi

        # outdir subdirs
        if [[ ! -e ${MEM_MODL_OUTDIR}/restarts/ ]]; then  # subdirectories
            mkdir -p ${MEM_MODL_OUTDIR}/restarts/
            mkdir -p ${MEM_MODL_OUTDIR}/restarts/vector/ 
            mkdir ${MEM_MODL_OUTDIR}/restarts/tile/            
        fi
        #TODO: Do we need this?
        mkdir -p ${MEM_MODL_OUTDIR}/noahmp/
        ln -sf ${MEM_MODL_OUTDIR}/noahmp ${MEM_WORKDIR}/noahmp_output 
    done 
fi

# Forcing perturbation goes here
if [[ $do_enkf == "YES" ]]; then 

    # Make sure the INPUT and RESTART dirs for stochy are in working dir
    # and input.nml has settings right
    
    stochy_init_exists="NO"

    if [[ ! -e ${WORKDIR}/RESTART ]]; then
        mkdir -p ${WORKDIR}/RESTART
        if [[ -e ${stochy_init_dir} ]]; then
            cp $stochy_init_dir/* ${WORKDIR}/RESTART  
            stochy_init_exists="YES"         
        else
            echo "directory for Stochy init files $stochy_init_dir doesn't exist, STOCH_INI_VAL will be set to FALSE"
        fi
    fi

    if [[ ! -e ${WORKDIR}/INPUT ]]; then
        mkdir -p ${WORKDIR}/INPUT
        for it in 1 2 3 4 5 6 
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

    cp ${CYCLEDIR}/template.input.nml $WORKDIR/input.nml
    if [[ $stochy_init_exists == "YES" ]]; then               # true for cycling with temporal correlation 
        sed -i -e "s/XXSTOCH_INI_VAL/.TRUE./g" $WORKDIR/input.nml
    else
        sed -i -e "s/XXSTOCH_INI_VAL/.FALSE./g" $WORKDIR/input.nml
    fi
    # sed -i -e "s/XXRES/${RES}/g"  $WORKDIR/input.nml
    sed -i -e "s/XXLX/${LayX}/g"  $WORKDIR/input.nml          # Layout
    sed -i -e "s/XXLY/${LayY}/g"  $WORKDIR/input.nml
    sed -i -e "s/XXIOLX/${IOLayX}/g"  $WORKDIR/input.nml      # IO Layout
    sed -i -e "s/XXIOLY/${IOLayY}/g"  $WORKDIR/input.nml
    sed -i -e "s/XXRES/${RES}/g"  $WORKDIR/input.nml
    RESP1=$((RES+1))
    sed -i -e "s/XXREP/${RESP1}/g"  $WORKDIR/input.nml 
    sed -i -e "s/XXNTIL/${num_tiles}/g"  $WORKDIR/input.nml       # Number of tiles
    sed -i -e "s/XXGRT/${grid_type}/g"  $WORKDIR/input.nml        # grid type -1 for FV3
    sed -i -e "s/XXLSC/${lndp_hscale}/g"  $WORKDIR/input.nml      # Spatial/horizontal correlation length = 120000 m
    sed -i -e "s/XXTAU/${lndp_tscale}/g"  $WORKDIR/input.nml      # Time correlation scale = 86400 s
   
fi

# copy ICS into restarts, if needed 
mem_ens="mem000"  # single member, us ensemble 0
rst_out=${OUTDIR}/${mem_ens}/restarts/vector/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
rst_in=${ICSDIR}/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
# if restart not in experiment out directory, copy the restarts from the ICSDIR
if [[ ! -e ${rst_out} ]]; then 
    echo "Looking for ICS: ${rst_in}"
    if [[ -e ${rst_in} ]]; then
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
fi 

if [[ "$ensemble_size" -gt 1  ]]; then  

    for ie in $(seq $ensemble_size)     
    do
        mem_ens="mem`printf %03i $ie`"
        rst_out=${OUTDIR}/${mem_ens}/restarts/vector/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
        rst_in=${ICSDIR}/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
        # if restart not in experiment out directory, copy the restarts from the ICSDIR
        if [[ ! -e ${rst_out} ]]; then 
            echo "Looking for ICS: ${rst_in}"
            if [[ -e ${rst_in} ]]; then
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
        fi 
    done
fi

# create dates file 
touch analdates.sh 
cat << EOF > analdates.sh
STARTDATE=$STARTDATE
ENDDATE=$ENDDATE
EOF

# submit script 
sbatch submit_cycle.sh
