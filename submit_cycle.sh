#!/bin/bash -le 
#SBATCH --job-name=offline_noahmp
#SBATCH --account=da-cpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --tasks-per-node=6
#SBATCH --cpus-per-task=1
#SBATCH -t 00:30:00
#SBATCH -o erlog_noahmp.%j
#SBATCH -e erlog_noahmp.%j
##SBATCH -t 02:40:00
##SBATCH --qos=batch
##SBATCH --nodes=2
##SBATCH --tasks-per-node=36

############################
# loop over time steps

echo 'starting cycle' 
date
source $analdate 

THISDATE=$STARTDATE
date_count=0

#stochy_init_found=${stochy_init_found:-"NO"}

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
    PREVDATE=`${incdate} $THISDATE -$PCYC_DEL`     
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
        cp  ${CYCLEDIR}/template.vector2tile $WORKDIR/vector2tile.namelist

        sed -i -e "s/XXYYYY/${YYYY}/g" vector2tile.namelist
        sed -i -e "s/XXMM/${MM}/g" vector2tile.namelist
        sed -i -e "s/XXDD/${DD}/g" vector2tile.namelist
        sed -i -e "s/XXHH/${HH}/g" vector2tile.namelist
        sed -i -e "s/XXRES/${RES}/g" vector2tile.namelist
        sed -i -e "s/XXTSTUB/${TSTUB}/g" vector2tile.namelist
        sed -i -e "s#XXTPATH#${TPATH}#g" vector2tile.namelist

        # submit vec2tile 
        echo '************************************************'
        echo 'calling vector2tile' 
        source ${CYCLEDIR}/land_mods

        ############################
        # copy restarts to workdir, convert to tile for DA (all members) 

	    # for LETKF mem000 holds ensemble mean
        mem_ens="mem000" 
        MEM_WORKDIR=${WORKDIR}/${mem_ens}
        MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

        # copy restarts into work directory
        rst_in=${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_back.${YYYY}-${MM}-${DD}_${HH}-00-00.nc 
        rst_out=${MEM_WORKDIR}/ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc
        if [[ -e ${rst_in} ]]; then
            cp $rst_in $rst_out 
        else
            echo "restart not found ${rst_in}; exiting" 
            exit 
        fi

        cp $WORKDIR/vector2tile.namelist $MEM_WORKDIR

        cd $MEM_WORKDIR
        $vec2tileexec vector2tile.namelist
        if [[ $? != 0 ]]; then
            echo "vec2tile failed for mem000"
            exit 
        fi
        
        if [[ "$ensemble_size" -gt 1  ]]; then 
            #TODO: parallelize this 
            for ie in $(seq $ensemble_size)
            do
                mem_ens="mem`printf %03i $ie`"
                MEM_WORKDIR=${WORKDIR}/${mem_ens}
                MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

                # copy restarts into work directory
                rst_in=${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_back.${YYYY}-${MM}-${DD}_${HH}-00-00.nc 
                rst_out=${MEM_WORKDIR}/ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc
                if [[ -e ${rst_in} ]]; then
                    cp $rst_in $rst_out 
                else
                    echo "restart not found ${rst_in}; exiting" 
                    exit 
                fi
                cp $WORKDIR/vector2tile.namelist $MEM_WORKDIR/vector2tile.namelist

                #TODO: parallelize this 
                cd $MEM_WORKDIR
                $vec2tileexec vector2tile.namelist
                if [[ $? != 0 ]]; then
                    echo "vec2tile failed for ens mem $ie"
                    exit 
                fi
               
            done
            # wait
        fi

        # ############################
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

        cd $WORKDIR

        # ############################
        # #  convert back to vector, run model (all members) 

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

        # mem000 is either for 1 member cases (2DVar) or LETKF ens mean	
        mem_ens="mem000" 
        MEM_WORKDIR=${WORKDIR}/${mem_ens}
        MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

        cp ${WORKDIR}/tile2vector.namelist $MEM_WORKDIR/tile2vector.namelist

        cd $MEM_WORKDIR
        $vec2tileexec tile2vector.namelist
        if [[ $? != 0 ]]; then
            echo "tile2vector failed for $mem_ens"
            exit 
        fi
        # save analysis restart
        cp ${MEM_WORKDIR}/ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc ${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_anal.${YYYY}-${MM}-${DD}_${HH}-00-00.nc

        if [[ "$ensemble_size" -gt 1  ]]; then 

            for ie in $(seq $ensemble_size)
            do
                mem_ens="mem`printf %03i $ie`"
                MEM_WORKDIR=${WORKDIR}/${mem_ens}
                MEM_MODL_OUTDIR=${OUTDIR}/${mem_ens}

                cp ${WORKDIR}/tile2vector.namelist $MEM_WORKDIR/tile2vector.namelist

                cd $MEM_WORKDIR
                $vec2tileexec tile2vector.namelist
                if [[ $? != 0 ]]; then
                    echo "tile2vector failed for ens mem "$ie
                    exit 
                fi

                # save analysis restart
                cp ${MEM_WORKDIR}/ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc ${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_anal.${YYYY}-${MM}-${DD}_${HH}-00-00.nc

            done
            # wait
        fi       
    fi
 
    # Forcing perturbation goes here
    if [[ $do_enkf == "YES" ]]; then 

        cd $WORKDIR
        
	cp ${CYCLEDIR}/template.input.nml $WORKDIR/input.nml

        if [[ $stochy_init_found == "YES" ]]; then
	    echo "stochy init patterns to be read from files"
            sed -i -e "s/XXSTOCH_INI_VAL/.TRUE./g" $WORKDIR/input.nml
        else
            sed -i -e "s/XXSTOCH_INI_VAL/.FALSE./g" $WORKDIR/input.nml
	    echo "stochy init patterns to be generated from seed"
        fi
    
        sed -i -e "s/XXRES/${RES}/g"  $WORKDIR/input.nml
        sed -i -e "s/XXLX/${LayX}/g"  $WORKDIR/input.nml          # Layout
        sed -i -e "s/XXLY/${LayY}/g"  $WORKDIR/input.nml
        sed -i -e "s/XXIOLX/${IOLayX}/g"  $WORKDIR/input.nml      # IO Layout
        sed -i -e "s/XXIOLY/${IOLayY}/g"  $WORKDIR/input.nml
    
        RESP1=$((RES+1))
    
        sed -i -e "s/XXREP/${RESP1}/g"  $WORKDIR/input.nml
        sed -i -e "s/XXNTIL/${num_tiles}/g"  $WORKDIR/input.nml       # Number of tiles
        sed -i -e "s/XXGRT/${grid_type}/g"  $WORKDIR/input.nml        # grid type -1 for FV3
        sed -i -e "s/XXLSC/${lndp_hscale}/g"  $WORKDIR/input.nml      # Spatial/horizontal correlation length = 120000 m
        sed -i -e "s/XXTAU/${lndp_tscale}/g"  $WORKDIR/input.nml      # Time correlation scale = 86400 s

        cp  ${CYCLEDIR}/template.generate_ens_forc_state.nml $WORKDIR/generate_ens_forc_state.nml

        forc_inp_file=${forcing_prefix}${YYYY}-${MM}-${DD}.nc  
        state_file_name=ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc

        sed -i -e "s#XXSTATICFILE#${static_file}#g" generate_ens_forc_state.nml
        sed -i -e "s#XXFORINPATH#${WORKDIR}#g" generate_ens_forc_state.nml
        sed -i -e "s#XXFORINFILE#${forc_inp_file}#g" generate_ens_forc_state.nml
        sed -i -e "s/XXSTATEFILE/${state_file_name}/g" generate_ens_forc_state.nml

        sed -i -e "s/YYYY/${YYYY}/g" generate_ens_forc_state.nml
        sed -i -e "s/MM/${MM}/g" generate_ens_forc_state.nml
        sed -i -e "s/DD/${DD}/g" generate_ens_forc_state.nml
        sed -i -e "s/HH/${HH}/g" generate_ens_forc_state.nml
        sed -i -e "s/XXRESX/${RES}/g" generate_ens_forc_state.nml   # TODO: Do these two (RESX/RESY) every differ?
        sed -i -e "s/XXRESY/${RES}/g" generate_ens_forc_state.nml
        sed -i -e "s/XXNTIL/${num_tiles}/g" generate_ens_forc_state.nml   # Number of tiles
        sed -i -e "s/XXLX/${LayX}/g" generate_ens_forc_state.nml          # Layout
        sed -i -e "s/XXLY/${LayY}/g" generate_ens_forc_state.nml

        lndp_hscale_km=$((lndp_hscale/1000))
        lndp_tau_hr=$((lndp_tscale/3600))

        sed -i -e "s/XXLSC/${lndp_hscale_km}/g" generate_ens_forc_state.nml   # Horizontal correlation length = 120 Km
        sed -i -e "s/XXVSC/${lndp_vscale}/g" generate_ens_forc_state.nml      # Vertical correlation length = 800 m
        sed -i -e "s/XXTAU/${lndp_tau_hr}/g" generate_ens_forc_state.nml      # Time correlation scale = 24 
        sed -i -e "s/XXENSZ/${ensemble_size}/g" generate_ens_forc_state.nml   # Ensemble size 
        sed -i -e "s/XXDTSFCX/${PCYC_DEL}/g" generate_ens_forc_state.nml      # DELTSFC = 6 hr 
        sed -i -e "s/XXVECTSZ/${vector_size}/g" generate_ens_forc_state.nml   # Noahmp vector array length, check from static file 
        
	if [[ ${perturb_forcing} -eq "YES" ]]; then
	    sed -i -e "s/XXPERTFORC/.true./g" generate_ens_forc_state.nml
        else
	    sed -i -e "s/XXPERTFORC/.false./g" generate_ens_forc_state.nml
	fi
        if [[ ${perturb_state} -eq "YES" ]]; then
            sed -i -e "s/XXPERTSTATE/.true./g" generate_ens_forc_state.nml
        else
            sed -i -e "s/XXPERTSTATE/.false./g" generate_ens_forc_state.nml
        fi

        forc_file=${forcing_dir}/${forc_inp_file}

        #TODO: fix Noahmp so the following two lines are not needed
        forc_inp_file_next=${forcing_prefix}${nYYYY}-${nMM}-${nDD}.nc
        forc_file_next=${forcing_dir}/${forc_inp_file_next}

        for ie in $(seq $ensemble_size)
        do
            mem_ens="mem`printf %03i $ie`" 
            cp ${forc_file} ${WORKDIR}/${mem_ens}/${forc_inp_file}   
            cp ${forc_file_next} ${WORKDIR}/${mem_ens}/${forc_inp_file_next}     #&
        done
        #wait

        # generate ensemble forcing
        echo 'Running Ens Forc Gen with Stochy'         #>> $logfile
        source ${CYCLEDIR}/stochy_mods        
        
        nt=$SLURM_NTASKS
        time srun '--export=ALL' --label -K -n $nt $EnsForcGenExe
        if [[ $? != 0 ]]; then
            echo "EnsForc Gen failed"
            exit 
        fi

        # for subsequent cycles use pattern saved in RESTART
	stochy_init_found="YES"

    fi

    ############################
    # run the forecast model

    cd $WORKDIR

    # update model namelist 
    cp  ${CYCLEDIR}/template.ufs-noahMP.namelist.${atmos_forc}  $WORKDIR/ufs-land.namelist

    sed -i -e "s/XXYYYY/${YYYY}/g" ufs-land.namelist
    sed -i -e "s/XXMM/${MM}/g" ufs-land.namelist
    sed -i -e "s/XXDD/${DD}/g" ufs-land.namelist
    sed -i -e "s/XXHH/${HH}/g" ufs-land.namelist
    sed -i -e "s/XXFREQ/${FREQ}/g" ufs-land.namelist
    sed -i -e "s/XXRDD/${RDD}/g" ufs-land.namelist
    sed -i -e "s/XXRHH/${RHH}/g" ufs-land.namelist

    if [[ $do_enkf == "YES" ]]; then 
        sed -i -e "s#XXFORCDIR#"./"#g" ufs-land.namelist
    else
	    sed -i -e "s#XXFORCDIR#${forcing_dir}#g" ufs-land.namelist
    fi

    echo '************************************************'
    echo "calling model"
    source ${CYCLEDIR}/land_mods
    module list

    nt=$((SLURM_NTASKS/ensemble_size))  #Note the extra tasks remain idle
    NPROC_NOMP=${NPROC_NOMP:-$nt}    

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
        time srun '--export=ALL' --label -K -n $NPROC_NOMP $LSMexec   &
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

    cd $WORKDIR

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
            exit 
        fi

        if [[ $do_enkf == "YES" && "$ensemble_size" -gt 1 ]]; then
           
	        # delete forcing ens files
            rm -f ${MEM_WORKDIR}/${forc_inp_file}  
            rm -f ${MEM_WORKDIR}/${forc_inp_file_next}  

            # needed for ensemble mean computed below
            yes|cp -f ${MEM_WORKDIR}/ufs_land_restart.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc ${WORKDIR}/mem000/ufs_lr_mem${ie}.nc 
        fi
        
    done
    wait

    # for enkf/letkf get ens mean 
    if [[ $do_enkf == "YES" && "$ensemble_size" -gt 1 ]]; then

        # module load nco

        MEM_WORKDIR=${WORKDIR}/mem000
        MEM_MODL_OUTDIR=${OUTDIR}/mem000
        
        ncra -O ${MEM_WORKDIR}/ufs_lr_mem*.nc ${MEM_WORKDIR}/ufs_land_restart.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc

        if [[ -e ${MEM_WORKDIR}/ufs_land_restart.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc ]]; then 
            cp ${MEM_WORKDIR}/ufs_land_restart.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc ${MEM_MODL_OUTDIR}/restarts/vector/ufs_land_restart_back.${nYYYY}-${nMM}-${nDD}_${nHH}-00-00.nc
        else 
            echo "Something went wrong while generating ens mean file, exiting" 
            exit 
        fi
   
        rm -f ${MEM_WORKDIR}/ufs_lr_mem*.nc
        
    fi

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

echo 'all done with cycle, finishing' 
date

