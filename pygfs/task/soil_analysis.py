#!/usr/bin/env python3

import os
from logging import getLogger
from typing import Dict, List, Optional, Any
from pprint import pformat
import glob
import gzip
import tarfile
import numpy as np
from netCDF4 import Dataset
from pygfs.task.analysis import Analysis
from pygfs.jedi import Jedi
from wxflow import (AttrDict, Executable, FileHandler, WorkflowException,
                    to_fv3time, to_YMD, to_YMDH, to_timedelta, add_to_datetime,
                    to_julian,
                    rm_p, cp,
                    parse_j2yaml, save_as_yaml,
                    Jinja,
                    logit)
from pygfs.utils.process_soil_increments import smc_addincrements

logger = getLogger(__name__.split('.')[-1])


class SoilAnalysis(Analysis):
    """
    Class for JEDI-based global Soil analysis tasks 
    (adapted from global-workflow/ush/python/pygfs/task/snow_analysis.py)
    """

    @logit(logger, name="Analysis")
    def __init__(self, config: Dict[str, Any]):
        """Constructor global Soil analysis task

        This method will construct a global jedi based soil analysis task.
        This includes:
        - extending the task_config attribute AttrDict to include parameters required for this task
        - instantiate the Jedi attribute object

        Parameters
        ----------
        config: Dict
            dictionary object containing task configuration

        Returns
        ----------
        None
        """
        super().__init__(config)

        _res = int(self.task_config['CASE'][1:])

        # Extend task_config with variables repeatedly used across this class
        self.task_config.update(AttrDict(
            {
                'npx_ges': _res + 1,
                'npy_ges': _res + 1,
                'npz_ges': self.task_config.LEVS - 1,
                'npz': self.task_config.LEVS - 1,
                'soil_bkg_path': os.path.join('./', 'bkg'),
                'soil_prepobs_path': os.path.join(self.task_config.DATA, 'prep'),
            }
        ))

        # Extend task_config with content of config yaml for this task
        self.task_config.update(parse_j2yaml(self.task_config.TASK_CONFIG_YAML, self.task_config))

        # Create JEDI object dictionary
        expected_keys = ['soilanlvar', 'soilanladdinc']
        self.jedi_dict = Jedi.get_jedi_dict(self.task_config.jedi_config, self.task_config, expected_keys)

    @logit(logger)
    def initialize(self) -> None:
        """Initialize a global land/soil analysis

        This method will initialize a global soil analysis.
        This includes:
        - stage input files from COM and create output directories
        - initialize JEDI applications

        Parameters
        ----------
        None

        Returns
        ----------
        None
        """

        # Stage files from COM
        logger.info(f"Staging files from COM and creating output directories")
        FileHandler(self.task_config.data_in).sync()

        # initialize JEDI variational application
        logger.info(f"Initializing JEDI applications")
        self.jedi_dict['soilanlvar'].initialize(self.task_config)  #, clean_empty_obsspaces=False)
        self.jedi_dict['soilanladdinc'].initialize(self.task_config)

    @logit(logger)
    def execute(self, jedi_dict_key: str) -> None:
        """Run JEDI executable

        This method will run JEDI executables for the global soil analysis

        Parameters
        ----------
        jedi_dict_key
            key specifying particular Jedi object in self.jedi_dict

        Returns
        ----------
        None
        """

        self.jedi_dict[jedi_dict_key].execute()

    @logit(logger)
    def finalize(self) -> None:
        """Performs closing actions of the Soil analysis task
        This method:
        - compress and tar output diag files in COM
        - save output files and YAMLs to COM

        Parameters
        ----------
        self : Analysis
            Instance of the SoilAnalysis object
        """

        # Compress and tar diag files into COM directory
#        self.tar_diag_files(self.task_config.COMOUT_SOIL_ANALYSIS,
#                            f"{self.task_config.APREFIX}soil_analysis.ioda_hofx.tar")

        # Save files to COM
        logger.info(f"Saving files to COM")
        FileHandler(self.task_config.data_out).sync()

    @logit(logger)
    def add_increments(self) -> None:
        """Executes the program "apply_incr.exe" to create analysis "sfc_data" files by adding increments to backgrounds

        Parameters
        ----------
        self : Analysis
            Instance of the SoilAnalysis object
        """

#TODO: figure out how to handle IAU cases for (offline) soil DA
        
        # need backgrounds to create analysis from increments after LETKF
        logger.info("Copy backgrounds into anl/ directory for creating analysis from increments")
        bkgtimes = []
        if self.task_config.DOIAU:
            # want analysis at beginning and middle of window
            bkgtimes.append(self.task_config.WINDOW_BEGIN)
        bkgtimes.append(self.task_config.current_cycle)
        anllist = []
        for bkgtime in bkgtimes:
            template = f'{to_fv3time(bkgtime)}.sfc_data.tile{{tilenum}}.nc'
            for itile in range(1, self.task_config.ntiles + 1):
                filename = template.format(tilenum=itile)
                src = os.path.join(self.task_config.COMIN_ATMOS_RESTART_PREV, filename)
                dest = os.path.join(self.task_config.DATA, "anl", filename)
                anllist.append([src, dest])
        FileHandler({'copy': anllist}).sync()

#TODO: Copy JEDI generated soil moisture increment files into anl/ directory
        # Copy increment files into anl/ directory
        logger.info("Copy pre-generated incrementi files from incr_path into anl/ directory")
        template_in = f'sfc_inc.tile{{tilenum}}.nc'
        template_out = f'soilinc.{to_fv3time(self.task_config.current_cycle)}.sfc_data.tile{{tilenum}}.nc'
        inclist = []
        for itile in range(1, self.task_config.ntiles + 1):
            filename_in = template_in.format(tilenum=itile)
            filename_out = template_out.format(tilenum=itile)
            src = os.path.join(self.task_config.incr_path, filename_in)
            dest = os.path.join(self.task_config.DATA, 'anl', filename_out)
            inclist.append([src, dest])
        FileHandler({'copy': inclist}).sync()

        # Apply increments per tile
        logger.info("Apply increments per tile")
        styp_template = f'{self.task_config.CASE}.{self.task_config.ORES}.soil_type.tile{{tilenum}}.nc'
        bkg_template  = f'{to_fv3time(self.task_config.current_cycle)}.sfc_data.tile{{tilenum}}.nc'
        inc_template  = f'soilinc.{to_fv3time(self.task_config.current_cycle)}.sfc_data.tile{{tilenum}}.nc'
        anl_template  = f'soilanl.{to_fv3time(self.task_config.current_cycle)}.sfc_data.tile{{tilenum}}.nc'

        smc_addincrements(
            anl_dir=os.path.join(self.task_config.DATA, "anl"),
            ntiles=self.task_config.ntiles,
            styp_template=styp_template,
            bkg_template=bkg_template,
            inc_template=inc_template,
            anl_template=anl_template,
            logger=logger,
        )

