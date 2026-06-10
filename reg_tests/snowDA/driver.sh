#!/bin/bash

#-----------------------------------------------------------------------------
#
# Run snow DA regression test on Ursa/Gaea.
#
# Set ./rt.control variables to specify the number of tasks, memory, and walltime
#
# Invoke the script from the command line as follows:  ./driver.sh
#
# Log output is placed in consistency.log??.  A summary is placed in summary.log
#
# A test fails when its output does not match the baseline files
# as determined by the 'nccmp' utility.  Baseline files are stored in HOMEreg.
#
#-----------------------------------------------------------------------------

set -x

submit_test() {
    local suffix="$1"; shift
    local ntasks_per_node="$1"; shift
    local nodes="$1"; shift
    local mem="$1"; shift
    local walltime="$1"; shift
    local exclusive="$1"; shift
    local jobname="$1"; shift
    local script="$1"; shift
    local waitonjobid="$1"; shift

    local logfile="${LOG_FILE}${suffix}"
    
    export DATA="${DATA_DIR}/test${suffix}"
    export COMOUT=$DATA

    if [[ "${exclusive}" == "true" ]]; then
        exclusive_flag="--exclusive"
    fi

    if [[ "${waitonjobid}" != "false" ]]; then
        dep_flag_slurm="--dependency=afterok:${waitonjobid}"
        dep_flag_pbs="-W depend=afterok:${waitonjobid}"
    fi

    if [[ "${SCHEDULER}" == "pbs" ]]; then
        export APRUNCY="mpiexec -n ${ntasks_per_node} -ppn ${ntasks_per_node} --cpu-bind core --depth ${OMP_NUM_THREADS_CY}"
        jobid=$(qsub -V -o "${logfile}" -e "${logfile}" -q "${QUEUE}" -A "${PROJECT_CODE}" -l walltime=${walltime} \
                -N "${jobname}" -l select=${nodes}:ncpus=${ntasks_per_node}:ompthreads=1:mem=${mem} \
                ${dep_flag_pbs:+"${dep_flag_pbs}"} "${script}")
        jobid=${jobid%.*}
    elif [[ "${SCHEDULER}" == "slurm" ]]; then
        export APRUNCY="srun"
        jobid=$(sbatch --parsable --partition="${partition}" --ntasks-per-node="${ntasks_per_node}" --nodes="${nodes}" --mem="${mem}" -t "${walltime}" \
               -A "${PROJECT_CODE}" -q "${QUEUE}" -J "${jobname}" --open-mode=append ${exclusive_flag:+"${exclusive_flag}"} \
               ${dep_flag_slurm:+"${dep_flag_slurm}"} -o "${logfile}" -e "${logfile}" "${script}")

        jobid=${jobid%.*}
    else
        echo "Error: Unsupported scheduler '${SCHEDULER}'"
        exit 1
    fi
    if [[ "${jobid}" == "" ]]; then
        echo "Error submitting job to scheduler"
        exit 1
    fi
    TEST_IDS+=(":${jobid}")
}

RT_DIR=${RT_DIR:-${PWD}}
notlocal=${notlocal:-false}
waitlocal=false
if [[ ${notlocal} == "false" ]]; then
  waitlocal=true
fi

if [[ -f "${RT_DIR}/../rt.control" ]]; then
    source "${RT_DIR}/../rt.control"
else
    echo "ERROR: Cannot find rt.control script"
    exit 1
fi

# Snow DA Test Cases
echo "========================================"
echo "Starting Snow DA Regression Tests"
echo "========================================"
echo ""

STMP="/scratch5/purged/"
LOG_FILE="${RT_DIR}/consistency.log"
DATA_DIR="${STMP}/${USER}/snowDA_regtest"

mkdir -p ${DATA_DIR}

# Get script directory for absolute paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Test directory: ${DATA_DIR}"
echo "Script directory: ${SCRIPT_DIR}"
echo ""

# Test 1: Snow DA with GHCN observations (LETKF)
echo "Test 01: Snow DA LETKF with GHCN observations"
echo "Submitting: C384.snowDA.letkf.ghcn.sh"
submit_test "01" "${NTASKS_SNOWANL}" "${NODES_SNOWANL}" "${MEM_SNOWANL}" "${WALLTIME_SNOWANL}" "${PARTITION}" "false" "snowDA_letkf_ghcn" "${SCRIPT_DIR}/C384.snowDA.letkf.ghcn.sh" "false"

echo "Test submission complete. Job IDs: ${TEST_IDS[@]}"
echo ""
echo "To monitor progress:"
echo "  squeue -u ${USER}"
echo "  tail -f ${LOG_FILE}*.log"
echo ""
echo "To check results after job completes:"
echo "  ${SCRIPT_DIR}/check_snowDA_tests.sh"
echo ""
