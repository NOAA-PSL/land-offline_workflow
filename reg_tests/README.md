# README: Flexible Regression Test Suite (rt.sh)

This script (rt.sh) automates the execution of regression test scenarios for the workflow. It manages configuration staging, Slurm job submission, queue monitoring, and final validation.

# Author: Yuan Xue (yuan.xue@noaa.gov)
# Date: 06/18/2026
# Note: Gemini was used to assist with developing this code and summarizing the scripts into a README. The code has been reviewed, edited, and validated by NWS staff.

-------------------------------------------------------------------------------
KEY FEATURES
-------------------------------------------------------------------------------
* Automated Matrix Testing: Sequentially executes predefined test scenarios
  configured in the script.
* Centralized Logging: Mirrors all console output into a local log file
  named 'summary.log'.

-------------------------------------------------------------------------------
DIRECTORY STRUCTURE EXPECTATIONS
-------------------------------------------------------------------------------
The script assumes it lives in a sub-directory (e.g., 'reg_tests/') directly
below the repository root:

repository_root/
├── do_submit_cycle.sh           # Main workflow submission script
├── [staged_config_files]        # Symlinked temporarily during execution
└── reg_tests/                   # Location of this test suite
    ├── rt.sh                    # Test runner script
    ├── summary.log              # Generated execution log
    ├── settings_cycle_* 	 # Cycle configuration files
    ├── settings_snowDA_* 	 # DA configuration files
    └── check_*.sh               # Scenario verification scripts

-------------------------------------------------------------------------------
HOW TO RUN
-------------------------------------------------------------------------------
Execute the script from its local directory:

    chmod +x rt.sh
    ./rt.sh

All standard output and error metrics are mirrored in real-time to the terminal
and saved to a local log file at 'reg_tests/summary.log'.

-------------------------------------------------------------------------------
MANAGING TEST CASES
-------------------------------------------------------------------------------
To add, remove, or modify test scenarios, edit the 'TEST_CASES' array at the
top of the script. Each entry must follow a space-separated format:

    "cycle_settings_file  da_settings_file  verification_script"

Example:
TEST_CASES=(
    "settings_cycle_test_C96_snow_letkf settings_snowDA_test_letkf  check_C96_letkf_snowDA_test.sh"
)
