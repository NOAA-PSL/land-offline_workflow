import os
import numpy as np
from netCDF4 import Dataset


def smc_addincrements(
    anl_dir,
    ntiles,
    styp_template,
    bkg_template,
    inc_template,
    anl_template,
    logger,
):
    """
    Full soil DA increment application over all tiles.

    Parameters
    ----------
    anl_dir : str
    ntiles : int
    *_template : str (filename templates)
    porosity_table : ndarray
    logger : logging.Logger
    """

    # Define freezing temp and porosity lookup table
    ice_threshold=1e-3
    tfreez=273.16
    porosity_table = np.array([
        0.339, 0.421, 0.434, 0.476,
        0.484, 0.439, 0.404, 0.464,
        0.465, 0.406, 0.468, 0.468,
        0.439, 1.000, 0.200, 0.421
    ])

    for itile in range(1, ntiles + 1):
        logger.info(f"Processing tile {itile}")

        # Build file paths
        styp_file = os.path.join(anl_dir, styp_template.format(tilenum=itile))
        bkg_file  = os.path.join(anl_dir, bkg_template.format(tilenum=itile))
        inc_file  = os.path.join(anl_dir, inc_template.format(tilenum=itile))
        anl_file  = os.path.join(anl_dir, anl_template.format(tilenum=itile))

        # Skip if missing increment
        if not os.path.exists(inc_file):
            logger.warning(f"No increment file for tile {itile}, skipping")
            continue

        tmp_file = anl_file + ".tmp"
        if os.path.exists(tmp_file):
            os.remove(tmp_file)

        # Open NetCDFs
        with Dataset(styp_file) as styp, \
             Dataset(bkg_file) as bkg, \
             Dataset(inc_file) as inc, \
             Dataset(tmp_file, "w") as anl:

            # Copy dimensions
            for name, dim in bkg.dimensions.items():
                anl.createDimension(
                    name,
                    len(dim) if not dim.isunlimited() else None
                )

            # Read variables
            slc_bkg = bkg.variables["slc"][:]
            smc_bkg = bkg.variables["smc"][:]
            stc_bkg = bkg.variables["stc"][:]
            slc_inc = inc.variables["slc"][:]

            if slc_bkg.shape != slc_inc.shape:
                raise ValueError(
                    f"Shape mismatch tile {itile}: "
                    f"{slc_bkg.shape} vs {slc_inc.shape}"
                )

            # Convert soil type to porosity
            soil_type = styp.variables["soil_type"][0, :, :].astype(np.int32)
            soil_idx = soil_type - 1

            if np.any((soil_idx < 0) | (soil_idx >= len(porosity_table))):
                raise ValueError(f"Invalid soil_type values in tile {itile}")

            porosity_2d = porosity_table[soil_idx]
            porosity_expanded = porosity_2d[None, None, :, :]

            # Create freeze mask
            soil_freeze = (stc_bkg[0] < tfreez) | (
                (smc_bkg[0] - slc_bkg[0]) > ice_threshold
            )

            not_frozen = (~soil_freeze)[None, :, :, :]

            # Apply increments
            slc_anl = np.where(not_frozen, slc_bkg + slc_inc, slc_bkg)
            smc_anl = np.where(not_frozen, smc_bkg + slc_inc, smc_bkg)

            # Physical constraints
            slc_anl = np.clip(slc_anl, 0.0, porosity_expanded)
            smc_anl = np.clip(smc_anl, 0.0, porosity_expanded)
            smc_anl = np.maximum(smc_anl, slc_anl)

            # Write output
            for name, var in bkg.variables.items():
                out = anl.createVariable(
                    name,
                    var.datatype,
                    var.dimensions
                )
                out.setncatts({k: var.getncattr(k) for k in var.ncattrs()})

                if name == "slc":
                    out[:] = slc_anl.astype(var.datatype)
                elif name == "smc":
                    out[:] = smc_anl.astype(var.datatype)
                else:
                    out[:] = var[:]

        # finalize file
        if os.path.exists(anl_file):
            os.remove(anl_file)
        os.rename(tmp_file, anl_file)

