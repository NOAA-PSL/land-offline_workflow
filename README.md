Script to run cycling DA using GDASApp in cube sphere space, and offline Noah-MP model in vector space. 

Clara Draper, Nov, 2021.

History 
Apr, 2022. Draper:  Moved to PSL repo, restructuring and renaming of repos.

May, 2023. Draper: Updated intel modules, added MPI for model.

Mar, 2024. Draper: Updated to Rocky8, switched to using GDASApp for JEDI executables. 

February, 2026. TZ Gichamo: add jcb-gdas, wxflow, and pygfs to generate the config/yaml files and handle workflow executions. 

April, 2026: TZ Gichamo: first pass 2DVar and LETKF soil DA for T2m and SMAP smc.

#############################

COMPILING and TESTING.

1. Fetch sub-modules.
>git submodule update --init --recursive

2. Compile sub-modules.

2a. load relevant modules for Ursa or GAEA C6
>source land_mods_ursa or source land_mods_gaeac6
(these are the modules needed for steps 2b, 2c).

2b. 
> cd ufs-land-driver

> configure 
  select ursa parallel or gaeac6 parallel 

> make

> cd ..

2c.
> cd vector2tile

> configure 
  select ursa parallel or gaeac6 parallel

> make

> cd .. 

2d.
> cd DA_update  (We no longer build GDASApp. Instead it is installed at directory shown in make_links)

> ./make_links.sh

> source env_GDASApp

> cd ..

* Note: DA_update does not include the GDASApp submodule. Its linked above, see README in DA_update 

2e. If you run NoahMP in ensemble mode (open loop or for LETKF DA)

> cd land_ensemble_gen

> source ../stochy_mods_ursa OR source ../stochy_mods_gaeac6

> ./compile_ens_intel

3. Run the test.

 In settings_cycle_test check BASEDIR, WORKDIR and OUTDIR are OK (comment/uncomment for URSA-vs-GAEAC6)
 
 Change the other settings (Make sure the obs dir, forcing dir, etc do exit--most of these are in Land DATA dir).

 In submit_cycle.sh make sure #SBATCH --account=  points to your own account (& (comment/uncomment for URSA-vs-GAEAC6).
 Also the number of processes, threads and time can be changed and synced with those set in settings. 
 Note that for bigger ensemble sizes (>4), you need to use large number of procs for the experiments to finish. Ideally the number of procs is set to be a multiple of 6 times the ensemble size (e.g., 120 for enssize=20, or bigger for high resolution experiments).
 
> do_submit_test.sh 

Once completed, to check snow DA output:

> (For snowDA) check_snowDA_test.sh

RUNNING YOUR OWN EXPERIMENTS 

1. Prepare a settings file, using settings_template. Must fill in all variables, unless otherwise commented. 

2. If running more than 6 tasks with JEDI, need to set layout = [x,y] in settings_cycle file. Make sure to modify submit_cycle.sh to ensure nnodes*tasks_per_node=NPROC_JEDI=6*x*y

3. Make sure there is a restart in your ICSDIR.

restart filename example:ufs_land_restart.2015-09-02_18-00-00.nc 
ICSDIR points to the experiment directory with the restart. If creating a new dircetory, the structure is: 
$ICSDIR/output/mem000/restarts/vector/ufs_land_restart.2015-09-02_18-00-00.nc 

4. in submit_cycle.sh make sure #SBATCH --account=  points to your own account.

5. Submit your job 

>do_submit_cycle.sh your-settings-filename

