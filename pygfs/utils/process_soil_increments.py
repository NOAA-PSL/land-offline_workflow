import re
import os
import numpy as np
from netCDF4 import Dataset


def smc_addincrements(
    anl_dir,
    obstype,
    ntiles,
    soil_parms,
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
    hfus=0.3336e06 # latent heat of fusion(j/kg)
    grav=9.80616   # gravity accel.(m/s2)

    # Read noahmp soil parameters
    params = read_noahmp_stas_params(
        soil_parms,
        var_list=["bb", "maxsmc", "satpsi"]
    )
    porosity_table = params["maxsmc"]
    bb_table = params["bb"]
    satpsi_table = params["satpsi"]

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

            # Read 2-layer increments
            slc1 = inc.variables["slc1_inc"][:]   # (Time, y, x)
            if obstype == "TQ2M":
                slc2 = inc.variables["slc2_inc"][:]
                stc1 = inc.variables["soilt1_inc"][:]
                stc2 = inc.variables["soilt2_inc"][:]

            # Get dimensions and create increment arrays
            nt, ny, nx = slc1.shape
            slc_inc = np.zeros((nt, 4, ny, nx), dtype=slc1.dtype)
            if obstype == "TQ2M":
                stc_inc = np.zeros((nt, 4, ny, nx), dtype=slc1.dtype)

            # Assign top two layers
            slc_inc[:, 0, :, :] = slc1   # layer 1 (top)
            if obstype == "TQ2M":
                slc_inc[:, 1, :, :] = slc2   # layer 2
                stc_inc[:, 0, :, :] = stc1   # layer 1 (top)
                stc_inc[:, 1, :, :] = stc2   # layer 2

            if slc_bkg.shape != slc_inc.shape:
                raise ValueError(
                    f"Shape mismatch tile {itile}: "
                    f"slc {slc_bkg.shape} vs {slc_inc.shape}, "
                )

            if obstype == "TQ2M" and stc_bkg.shape != stc_inc.shape:
                raise ValueError(
                    f"Shape mismatch tile {itile}: "
                    f"stc {stc_bkg.shape} vs {stc_inc.shape}"
                )

            # Convert soil type to porosity, satpsi, bb
            soil_type = styp.variables["soil_type"][0, :, :].astype(np.int32)
            soil_idx = soil_type - 1

            if np.any((soil_idx < 0) | (soil_idx >= len(porosity_table))):
                raise ValueError(f"Invalid soil_type values in tile {itile}")

            # Expand soil parameter fields
            porosity = porosity_table[soil_idx][None, None, :, :]
            satpsi   = satpsi_table[soil_idx][None, None, :, :]
            bb       = bb_table[soil_idx][None, None, :, :]
            porosity4 = np.broadcast_to(porosity, stc_bkg.shape)
            satpsi4   = np.broadcast_to(satpsi, stc_bkg.shape)
            bb4       = np.broadcast_to(bb, stc_bkg.shape)

            # Match state shape
            stc_anl = np.asarray(stc_bkg)
            if obstype == "TQ2M":
                stc_anl = np.asarray(stc_bkg + stc_inc)

            # Freeze mask
            soil_freeze = (stc_anl < tfreez) | (
                (smc_bkg - slc_bkg) > ice_threshold
            )

            not_frozen = (~soil_freeze)
            not_frozen = not_frozen.astype(bool)

            # Apply increments to soil moisture
            slc_anl = np.where(not_frozen, slc_bkg + slc_inc, slc_bkg)
            smc_anl = np.where(not_frozen, smc_bkg + slc_inc, smc_bkg)

            # frz/unfrz ==> frz, recalculate slc, smc remains
            mask = (stc_anl < tfreez - 1e-6)

            # Recompute supercool liquid water, smc_anl remain unchanged
            smp = np.zeros_like(stc_anl)
            smp[mask] = (
                hfus * (tfreez - stc_anl[mask]) /
                (grav * np.maximum(stc_anl[mask], 1e-6))
            )

            # Diagnostic liquid water (only frozen regime)
            slc_new = slc_anl.copy()

            slc_new[mask] = porosity4[mask] * (
                smp[mask] / np.maximum(satpsi4[mask], 1e-12)
            ) ** (-1.0 / np.maximum(bb4[mask], 1e-12) )

            # frz ==> unfrz, melt all soil ice (if any)
            slc_anl[~mask] = smc_anl[~mask]

            # blend: frozen physics overrides only frozen part
            slc_anl = np.where(mask, slc_new, slc_anl)

            # Physical constraints
            slc_anl = np.clip(slc_anl, 0.0, porosity4)
            smc_anl = np.clip(smc_anl, 0.0, porosity4)
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
                elif name == "stc":
                    out[:] = stc_anl.astype(var.datatype)
                else:
                    out[:] = var[:]

        # finalize file
        if os.path.exists(anl_file):
            os.remove(anl_file)
        os.rename(tmp_file, anl_file)

def read_noahmp_stas_params(file_path, var_list=None):
    """
    Extract soil parameters from &noahmp_soil_stas_parameters block.

    Parameters
    ----------
    file_path : str
        Path to noahmptable.tbl
    var_list : list[str] or None
        Variables to extract (e.g., ["bb", "maxsmc", "satpsi"]).
        If None, returns all variables in the block.

    Returns
    -------
    dict
        {var_name: np.ndarray(shape=(19,))}
    """

    data = {}
    in_block = False
    current_var = None

    with open(file_path, "r") as f:
        for line in f:

            line = line.strip()

            # detect block start
            if line.startswith("&noahmp_soil_stas_parameters"):
                in_block = True
                continue

            # detect block end
            if in_block and line.startswith("/"):
                break

            if not in_block:
                continue

            # skip comments / headers
            if not line or line.startswith("!"):
                continue

            # detect variable name line
            match = re.match(r"^([a-zA-Z0-9_]+)\s*=", line)
            if match:
                current_var = match.group(1).lower()

                values = re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", line)

                if values:
                    data[current_var] = np.array([float(v) for v in values])

            # continuation lines
            elif current_var is not None:
                values = re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", line)

                if values:
                    data[current_var] = np.concatenate([
                        data[current_var],
                        np.array([float(v) for v in values])
                    ])

    # filter requested variables
    if var_list is not None:
        var_list = [v.lower() for v in var_list]
        data = {k: v for k, v in data.items() if k in var_list}

    return data

