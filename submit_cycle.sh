#!/bin/bash -le 
#SBATCH --job-name=offline_noahmp
#SBATCH --account=da-cpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --tasks-per-node=6
#SBATCH --cpus-per-task=1
##SBATCH -t 02:40:00
##SBATCH --qos=batch
##SBATCH --nodes=2
##SBATCH --tasks-per-node=36
#SBATCH -t 00:10:00
#SBATCH -o log_noahmp.%j.log
#SBATCH -e err_noahmp.%j.err

############################
# loop over time steps

echo 'starting cycle' 
date
source $analdate 

export PCYC_DEL=${PCYC_DEL:- -6}

THISDATE=$STARTDATE
date_count=0

while [ $date_count -lt $cycles_per_job ]; do

    if [ $THISDATE -ge $ENDDATE ]; then 
        echo "All done, at date ${THISDATE}"  >> $logfile
        cd $CYCLEDIR 
        if [ $KEEPWORKDIR == "NO" ];   then 
            rm -rf $WORKDIR
        fi
        exit  
    fi

    echo "starting $THISDATE"  

    # get DA settings

    this_config=DA_config$HH
    DA_config=${!this_config}

    if [ $DA_config == "openloop" ]; then do_jedi="NO" ; else do_jedi="YES" ; fi 

    # substringing to get yr, mon, day, hr info
    YYYY=`echo $THISDATE | cut -c1-4`
    MM=`echo $THISDATE | cut -c5-6`
    DD=`echo $THISDATE | cut -c7-8`
    HH=`echo $THISDATE | cut -c9-10`

    # substringing to get yr, mon, day, hr info for previous cycle
    # PREVDATE=`${incdate} $THISDATE -6`
    PREVDATE=`${incdate} $THISDATE -${PCYC_DEL}` 
    YYYP=`echo $PREVDATE | cut -c1-4`
    MP=`echo $PREVDATE | cut -c5-6`
    DP=`echo $PREVDATE | cut -c7-8`
    HP=`echo $PREVDATE | cut -c9-10`
    
    # substring for next cycle
    NEXTDATE=`${incdate} $THISDATE $FCSTHR`
    nYYYY=`echo $NEXTDATE | cut -c1-4`
    nMM=`echo $NEXTDATE | cut -c5-6`
    nDD=`echo $NEXTDATE | cut -c7-8`
    nHH=`echo $NEXTDATE | cut -c9-10`

    cd $WORKDIR

    if [[ $do_jedi == "YES" ]]; then  
        # update vec2tile and tile2vec namelists
        # to-do: update location_end in template, for specific res. 
        # then template will be res-independent.
        cp  ${CYCLEDIR}/template.vector2tile vector2tile.namelist

        sed -i -e "s/XXYYYY/${YYYY}/g" vector2tile.namelist
        sed -i -e "s/XXMM/${MM}/g" vector2tile.namelist
        sed -i -e "s/XXDD/${DD}/g" vector2tile.namelist
        sed -i -e "s/XXHH/${HH}/g" vector2tile.namelist
        sed -i -e "s/XXHH/${HH}/g" vector2tile.namelist
        sed -i -e "s/XXRES/${RES}/g" vector2tile.namelist
        sed -i -e "s/XXTSTUB/${TSTUB}/g" vector2tile.namelist
        sed -i -e "s#XXTPATH#${TPATH}#g" vector2tile.namelist

        # submit vec2tile 
        echo '************************************************'
        echo 'calling vector2tile' 
        source ${CYCLEDIR}/land_mods

        ############################
        # copy restarts to workdir, convert to vector for DA (all members) 

        for ie in $(seq $ensemble_size)
        do
            # mem_ens="mem000" 
            if [[ "$ensemble_size" -eq 1  ]]; then 
                mem_ens="mem000" 
            else 
                mem_ens="mem`printf %03i $ie`"
            fi 

            MEM_WORKDIR=${WORKDIR}/${mem_ens}
            MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

            # copy restarts into work directory
            rst_in=${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_back.${YYYY}-${MM}-${DD}_${HH}-00-00.nc 
            rst_out=${MEM_WORKDIR}/ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc
            if [[ -e ${rst_in} ]]; then
                cp $rst_in $rst_out 
            else
                echo "restart not found ${rst_in}; exiting" 
                exit 10
            fi
            cp vector2tile.namelist $MEM_WORKDIR
#TODO: parallelize this 
            cd $MEM_WORKDIR
            $vec2tileexec vector2tile.namelist
            if [[ $? != 0 ]]; then
                echo "vec2tile failed for ens mem $ie"
                # for i in $(seq 6) do 
                #     tile_out = ${MEM_WORKDIR}/${YYYY}-${MM}-${DD}_${HH}-00-00_sfc_data.tile$i.nc
                #     rm $tile_out
                # done
                exit 
            fi
            # rm $rst_out
        done
        # wait
    # fi # vector2tile for DA

    # ############################
    # # do DA update

    # if [[ $do_jedi == "YES" ]]; then  

        # submit snow DA 
        echo '************************************************'
        echo 'CSD calling snow DA'

        cd $WORKDIR

        export THISDATE
        $DAscript ${CYCLEDIR}/$DA_config
        if [[ $? != 0 ]]; then
            echo "land DA script failed"
            exit
        fi   
    # fi 

        cd $WORKDIR

    # ############################
    # #  convert back to vector, run model (all members) 

    # if [[ $do_jedi == "YES" ]]; then  

        echo '************************************************'
        echo 'calling tile2vector' 
        source ${CYCLEDIR}/land_mods

        cp  ${CYCLEDIR}/template.tile2vector tile2vector.namelist

        sed -i -e "s/XXYYYY/${YYYY}/g" tile2vector.namelist
        sed -i -e "s/XXMM/${MM}/g" tile2vector.namelist
        sed -i -e "s/XXDD/${DD}/g" tile2vector.namelist
        sed -i -e "s/XXHH/${HH}/g" tile2vector.namelist
        sed -i -e "s/XXRES/${RES}/g" tile2vector.namelist
        sed -i -e "s/XXTSTUB/${TSTUB}/g" tile2vector.namelist
        sed -i -e "s#XXTPATH#${TPATH}#g" tile2vector.namelist

        for ie in $(seq $ensemble_size)
        do
            # mem_ens="mem000" 
            if [[ "$ensemble_size" -eq 1  ]]; then 
                mem_ens="mem000" 
            else 
                mem_ens="mem`printf %03i $ie`"
            fi 

            MEM_WORKDIR=${WORKDIR}/${mem_ens}
            MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

            cp ${WORKDIR}/tile2vector.namelist $MEM_WORKDIR/tile2vector.namelist

            cd $MEM_WORKDIR
            $vec2tileexec tile2vector.namelist
            if [[ $? != 0 ]]; then
                echo "tile2vector failed for ens mem "$ie
                # rm $rst_out
                exit 
            fi

            # save analysis restart
            cp ${MEM_WORKDIR}/ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc ${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_anal.${YYYY}-${MM}-${DD}_${HH}-00-00.nc

            # for i in $(seq 6) do 
            #     tile_out = ${MEM_WORKDIR}/${YYYY}-${MM}-${DD}_${HH}-00-00_sfc_data.tile$i.nc
            #     rm $tile_out
            # done
        done
        # wait

    fi

# Forcing perturbation goes here
    if [[ $do_enkf == "YES" ]]; then 

        #cp template.input.nml input.nml
        cp  ${CYCLEDIR}/template.generate_ens_forc.nml generate_ens_forc.nml

        forc_inp_file=${forcing_prefix}${YYYY}-${MM}-${DD}.nc  #C${RES}_GDAS_forcing_${YYYY}-${MM}-${DD}.nc

        sed -i -e "s/FORINPFILE/${forc_inp_file}/g" generate_ens_forc.nml
        sed -i -e "s/YYYY/${YYYY}/g" generate_ens_forc.nml
        sed -i -e "s/MM/${MM}/g" generate_ens_forc.nml
        sed -i -e "s/DD/${DD}/g" generate_ens_forc.nml
        sed -i -e "s/HH/${HH}/g" generate_ens_forc.nml
        sed -i -e "s/XXRES/${RES}/g" generate_ens_forc.nml

        # Make sure the INPUT and RESTART dirs for stochy are in working dir
        # and input.nml has settings right  

        cp ${CYCLEDIR}/template.input.nml input.nml
        if [[ $stochy_init_exist == "YES" ]]; then
           sed -i -e "s/STOCH_INI_VAL/.TRUE./g" input.nml
        else
           sed -i -e "s/STOCH_INI_VAL/.FALSE./g" input.nml
        fi

        if [[ ! -e ${WORKDIR}/INPUT ]]; then
            mkdir -p ${WORKDIR}/INPUT
        fi

        if [[ ! -e ${WORKDIR}/RESTART ]]; then
            mkdir -p ${WORKDIR}/RESTART
            if [[ ! -e ${stochy_init_dir} ]]; then
                echo "Error! the directory forStochy init files ${stochy_init_dir} doesn't exist"
                exit
            else
                cp $stochy_init_dir/* ${WORKDIR}/RESTART
            fi
        fi

        forc_file=${forcing_dir}/${forc_inp_file}
        for ie in $(seq $ensemble_size)
        do
            mem_ens="mem`printf %03i $ie`" 
            cp ${forc_file} ${WORKDIR}/${mem_ens}   &
        done
        # wait

        # generate ensemble forcing
        echo 'Running Ens Forc Gen with Stochy'         #>> $logfile
        source ${cycle_dir}/modules_stochy.sh
        
        module list
        
        nt=$SLURM_NTASKS
        time srun '--export=ALL' --label -K -n $nt $EnsForcGenExe
        if [[ $? != 0 ]]; then
            echo "EnsForc Gen failed"
            exit 10
        fi

    fi

    ############################
    # run the forecast model

    cd $WORKDIR

    # update model namelist 
    cp  ${CYCLEDIR}/template.ufs-noahMP.namelist.${atmos_forc}  ufs-land.namelist

    sed -i -e "s/XXYYYY/${YYYY}/g" ufs-land.namelist
    sed -i -e "s/XXMM/${MM}/g" ufs-land.namelist
    sed -i -e "s/XXDD/${DD}/g" ufs-land.namelist
    sed -i -e "s/XXHH/${HH}/g" ufs-land.namelist
    sed -i -e "s/XXFREQ/${FREQ}/g" ufs-land.namelist
    sed -i -e "s/XXRDD/${RDD}/g" ufs-land.namelist
    sed -i -e "s/XXRHH/${RHH}/g" ufs-land.namelist

    echo '************************************************'
    echo "calling model"
    source ${CYCLEDIR}/land_mods
    module list

    nt=$((SLURM_NTASKS/ensemble_size))  #Note the extra tasks remain idle
    
    for ie in $(seq $ensemble_size)
    do
        if [[ "$ensemble_size" -eq 1  ]]; then 
            mem_ens="mem000" 
        else 
            mem_ens="mem`printf %03i $ie`"
        fi 

        MEM_WORKDIR=${WORKDIR}/${mem_ens}
        # echo "member working dir $MEM_WORKDIR"

        cp $WORKDIR/ufs-land.namelist $MEM_WORKDIR/ufs-land.namelist    

        # run for using baseline snow parameter table
        cp ${CYCLEDIR}/ufs-land-driver/ccpp-physics/physics/SFC_Models/Land/Noahmp/noahmptable.tbl $MEM_WORKDIR/noahmptable.tbl 

        cd $MEM_WORKDIR
            
#TODO: modify NoahMP to have mpi-group for each ensemble member and compare runtimes
        time srun '--export=ALL' --label -K -n $nt $LSMexec   &
        # #-N1-1 --exclusive

        # # srun -l --multi-prog $lsm_tasks_file

# no error codes on exit from model, check for restart below instead
# TODO: Modify noahmp to exit with error code    
        # if [[ $? != 0 ]]; then
        #     echo "NoahMP failed for ensemble $ie"
        #     exit 10
        # fi   
    done
    wait

    ############################
    # check model ouput (all members)

    for ie in $(seq $ensemble_size)
    do
        if [[ "$ensemble_size" -eq 1  ]]; then 
            mem_ens="mem000" 
        else 
            mem_ens="mem`printf %03i $ie`"
        fi 

        MEM_WORKDIR=${WORKDIR}/${mem_ens}
        MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

        if [[ -e ${MEM_WORKDIR}/ufs_land_restart.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc ]]; then 
            cp ${MEM_WORKDIR}/ufs_land_restart.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc ${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_back.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc
        else 
            echo "Restart couldn't be found: ${MEM_WORKDIR}/ufs_land_restart.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc"
            echo "probably model runtime error occurred, exiting" 
            exit 10
        fi

        # delete forcing ens files
        if [[ $do_enkf == "YES" ]]; then
            rm ${MEM_WORKDIR}/${forc_inp_file}
        fi
        
    done
    # wait

    echo "Finished job number, ${date_count},for  date: ${THISDATE}" >> $logfile

    THISDATE=$NEXTDATE
    date_count=$((date_count+1))

done #  date_count -lt cycles_per_job


############################
# resubmit script 

if [ $THISDATE -lt $ENDDATE ]; then
    echo "STARTDATE=${THISDATE}" > ${analdate}
    echo "ENDDATE=${ENDDATE}" >> ${analdate}
    cd ${CYCLEDIR}
    sbatch ${CYCLEDIR}/submit_cycle.sh
fi

echo 'all done with cycle, exiting' 
date

