Script to run cycling DA using JEDI in cube sphere space, and offline Noah-MP model in vector space. 

Clara Draper, Nov, 2021.

History 
Apr, 2022. Draper:  Moved to PSL repo, restructuring and renaming of repos.
May, 2023. Draper: Updated intel modules, added MPI for model.
Mar, 2024. Draper: Updated to Rocky8, switched to using GDASApp for JEDI executables. 

#############################

COMPILING and TESTING.

1. Fetch sub-modules.
>git submodule update --init --recursive

2. Compile sub-modules.

2a. 
>load land_mods
(these are the modules needed for steps 2b, 2c).

2b.
> cd vector2tile 
> configure 
     select hera
> make 
> cd .. 

2c. 
> cd ufs-land-driver
> configure 
  select hera parallel
> make 
> cd ..

2d.
> cd DA_update
> build_all.sh 
> cd .. 

3. Run the test.

 in settings_cycle_test check WORKDIR and OUTDIR are OK
 create OUTDIR
 in submit_cycle.sh change #SBATCH --account=gsienkf to point to your own account.

> do_submit_test.sh 

Once completed:

> check_test.sh

RUNNING YOUR OWN EXPERIMENTS 

1. Prepare a settings file, using settings_template. Must fill in all variables, unless otherwise commented. 

2. If running more than 6 tasks with JEDI, need to set layout = [x,y] in yaml, such that ntasks = 6*x*y

3. Make sure there is a restart in your ICSDIR.

restart filename example:ufs_land_restart.2015-09-02_18-00-00.nc 
ICSDIR points to the experiment directory with the restart. If creating a new dircetory, the structure is: 
$ICSDIR/output/mem000/restarts/vector/ufs_land_restart.2015-09-02_18-00-00.nc 

4. in submit_cycle.sh change #SBATCH --account=gsienkf to point to your own account.

5. Submit your job 

>do_submit_cycle.sh your-settings-filename


###################################################
IGNORE THIS - OUTDATED.

Jong's instructions for compiling with CMake.

1. git clone -b feature/bundle-cmake https://github.com/jkbk2004/land-offline_workflow-1

2. cd land-offline_workflow-1/

3. git submodule update --init --recursive

4. mkdir build

5. source configures/machine.orion.intel

6. cd build/

7. ecbuild ..

8. make -j 1

