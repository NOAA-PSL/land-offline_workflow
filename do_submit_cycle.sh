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
if [[ "$ensemble_size" -gt 1  ]]; then           
    for ie in $(seq $ensemble_size)     
    do
        mem_ens="mem`printf %03i $ie`"
        mkdir ${WORKDIR}/${mem_ens}              
    done    
fi

# outdir and subdirs
# vector and tile dirs top of mem_ens dirs to facilitate parallel run
if [[ ! -e ${OUTDIR} ]]; then
    mkdir -p  ${OUTDIR}
    # if [[ ! -e ${OUTDIR}/vector/ ]]; then  # subdirectories  
    mkdir -p ${OUTDIR}/vector/ 
    mkdir -p ${OUTDIR}/tile/ 
    #TODO: Do we need this?
    mkdir -p ${OUTDIR}/noahmp/ 
   
    # ensemble outdir (model only)
    mem_ens="mem000"  # single member, us ensemble 0
    MEM_MODL_OUTDIR=${OUTDIR}/vector/${mem_ens}
    # if [[ ! -e $MEM_MODL_OUTDIR ]]; then  #ensemble outdir 
    mkdir -p $MEM_MODL_OUTDIR
    mkdir -p ${OUTDIR}/tile/${mem_ens}
    mkdir -p ${OUTDIR}/noahmp/${mem_ens}   

    if [[ "$ensemble_size" -gt 1  ]]; then           
        for ie in $(seq $ensemble_size)     
        do
            mem_ens="mem`printf %03i $ie`"
            mkdir -p ${OUTDIR}/vector/${mem_ens}    
            mkdir -p ${OUTDIR}/tile/${mem_ens} 
            mkdir -p ${OUTDIR}/noahmp/${mem_ens}            
        done 
    fi
    #TODO: Do we need this?
    ln -sf ${OUTDIR}/noahmp ${WORKDIR}/noahmp_output    
fi

# copy ICS into restarts, if needed 
mem_ens="mem000"  # single member, us ensemble 0
MEM_MODL_OUTDIR=${OUTDIR}/vector/${mem_ens}
rst_out=${OUTDIR}/vector/${mem_ens}/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
rst_in=${ICSDIR}/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
# if restart not in experiment out directory, copy the restarts from the ICSDIR
if [[ ! -e ${rst_out} ]]; then 
    echo "Looking for ICS: ${rst_in}"
    if [[ -e ${rst_in} ]]; then
       echo "ICS found, copying" 
       cp ${rst_in} ${rst_out}
    else  # check if is in output directory structure
        rst_in=${ICSDIR}/vector/${mem_ens}/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
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
        rst_out=${OUTDIR}/vector/${mem_ens}/ufs_land_restart_back.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
        rst_in=${ICSDIR}/vector/${mem_ens}/ufs_land_restart.${sYYYY}-${sMM}-${sDD}_${sHH}-00-00.nc
        # if restart not in experiment out directory, copy the restarts from the ICSDIR
        if [[ ! -e ${rst_out} ]]; then 
            echo "Looking for ICS: ${rst_in}"
            if [[ -e ${rst_in} ]]; then
                echo "ICS found, copying" 
                cp ${rst_in} ${rst_out}
            else                  
                echo "ICS not found. Exiting" 
                exit 10 
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
echo "submitting cycle"
sbatch submit_cycle.sh
