
# LH2 Transfer Simulation

> ## About this fork
>
> This is a modified fork of [LLNL/LH2Transfer](https://github.com/LLNL/LH2Transfer).
> **The REFPROP licence requirement has been removed.** Parahydrogen properties
> are supplied by the open-source [CoolProp](http://www.coolprop.org/) library
> through a drop-in `refpropm.m` shim, so no call site in the original code was
> changed.
>
> Two further changes were needed to run the code end to end: a missing file
> (`vaporpressure_bis.m`) was reconstructed, and the post-processing loop was
> preallocated. All seven of the original REFPROP-derived polynomial fits are
> **retained unchanged**, so results stay comparable to Petitpas (2018).
>
> See **[NOTICE.md](NOTICE.md)** for the full list of alterations (required by
> the NASA Open Source Agreement) and **[SHIM_NOTES.md](SHIM_NOTES.md)** for the
> technical detail and validation evidence.
>
> Verified with MATLAB R2026a, Python 3.13, CoolProp 8.0.0 on Windows 11.
> The original code was developed against MATLAB R2013b and REFPROP 9.1.

---

The code LH2TS (for “LH2 Transfer Simulation”) enables to calculate the wasted H2 due to transfer and boil-off while using LH2 as a fuel for transportation. More specifically, a reduced lumped-parameter model simulates thermodynamic states in 2 vessels (one feeding, one receiving) using mass and energy balances for each control volume (vapor and liquid, in each vessel) and relying on 2-phase behavior and heat transfer models specific to cryogenic fluids (self consistent theory of dynamical condensation/evaporation – see references for details).
This code was developed and tested using MATLAB R2013b and REFPROP DLL version 9.1 for parahydrogen [1], on a laptop PC running on 64-bit Windows 10 Enterprise (2016), with an Intel Core -7-6600U CPU @ 2.60 GHz and a 16.0 GB RAM.

# Description of the files

The simulation code consists of 13 MATLAB files that should be located in the same folder.
The first nine are from the original release; the last four were added or
reconstructed in this fork (see [NOTICE.md](NOTICE.md)).

**From the original release:**
-	runNominal.m : runs the overall code

-	inputs_TrailerToDewar.m : initializes the inputs and boundary conditions

-	LH2Control.m : controls the different steps of the fill process

-	LH2Simulate.m : solves the governing ordinary integro-differential equations using an ODE solver (odes15s)

-	Data_extraction.m : post-processes output data

-	cylVtoH.m: function used in the post-process step. Converts volume of LH2 in a horizontal cylinder to a height of fluid

-	gasFlow.m: function used in the post-process step. Calculates the flow rates (chocked or not) between 2 vessels.

-	vaporpressure.m: function used in the post-process step. Calculates vapor pressure (2 phases or not) based on temperature and density.

-	plotLH2Data.m : plots output data, in multiple separate figures

**Added in this fork:**

-	refpropm.m : drop-in replacement for the NIST REFPROP MATLAB wrapper, backed by CoolProp. Implements the same signature, units and quality-flag conventions

-	vaporpressure_bis.m : required by Data_extraction.m but absent from the original release. Reconstructed verbatim from the local subfunction at LH2Simulate.m:860. Calculates vapor pressure based on **internal energy** and density (note: vaporpressure.m is a different function, taking temperature and density, and is shadowed by a local subfunction during the solve)

-	validate_shim.m : validation harness. Run this before runNominal.m; it must report ALL CHECKS PASSED

-	SHIM_NOTES.md : documentation of the CoolProp substitution, the REFPROP 9.1 cross-check, and an audit of the hardcoded polynomial fits


Running runNominal.m with the MATLAB software will solve governing equations and save the results in “output.txt”, located in the same folder as the other files. Please refer to runNominal.m for the nomenclature of the output file.

The code architecture and underlying physical phenomena are based on the work of Muratov, Daigle, Osipov et al [2-5], who kindly shared their original code that was released as open-source. More information on the code can be found in the references. 

Modifications were made to the original version, including new shape factors, real gas equations of state linked to REFPROP for both thermodynamics and transport properties, new energy equations for the liquid phases, energy balances based on internal energies (as opposed to temperature). Polynomial expressions derived from REFPROP were used in some instances (e.g. saturated liquid density as a function of internal energy, enthalpy of vaporization as a function of film temperature).

The code has been verified only for “typical” thermodynamic states of H2 (i.e. temperatures, pressures and densities close to or within the 2 phase region). Atypical scenarios such as the cool-down with LH2 of a warm vessel have not been verified and the code would likely need additional modifications in order to adequately simulate those scenarios.

# Requirements

*This section replaces the original REFPROP linking instructions. See
[NOTICE.md](NOTICE.md).*

This fork does **not** require a REFPROP licence. It requires:

- MATLAB (tested on R2026a; the original was developed on R2013b)
- Python 3, configured in MATLAB via `pyenv`. Use
  `pyenv(ExecutionMode="InProcess")`; the out-of-process mode adds a process
  boundary to every property call, of which the solver makes roughly 68 per
  right-hand-side evaluation.
- CoolProp: `py -m pip install CoolProp`

Verify the installation before running anything:

```matlab
>> validate_shim
```

This must report `ALL CHECKS PASSED`. A mis-mapped property code produces
figures that look entirely plausible and are wrong, so do not skip it.

Then:

```matlab
>> runNominal
```

*For reference, the original instructions were: REFPROP must be installed in
"Program Files (x86)" with REFPRP64_thunk_pcwin64.dll in that directory; see
http://trc.nist.gov/refprop/LINKING/Linking.htm (last accessed 12/7/2017).*

# References

[1] Lemmon, E.W., Huber, M.L., McLinden, M.O.  NIST Standard Reference Database 23:  Reference Fluid Thermodynamic and Transport Properties-REFPROP, Version 9.1, National Institute of Standards and Technology, Standard Reference Data Program, Gaithersburg, 2013.

[2] V. V. Osipov and C. B. Muratov, “Dynamic condensation blocking in cryogenic refueling,” Applied Physics Letters, vol. 93, no. 22, pp. 224 105–1–4, 2008.

[3] V. Osipov, C. Muratov, M. Daigle, M. Foygel, V. Smelyanskiy, and A. Patterson-Hine, “A dynamical
physics model of nominal and faulty operational modes of propellant loading (liquid hydrogen): From space shuttle to future missions,” NASA Ames Research Center, Tech. Rep. NASA/TM-2010-216394, Jul. 2010.

[4] M. Daigle, S. Lee, C. Muratov, S. Osipov, V. Smelyanskiy, and  Michael Foygel, “LH2 Matlab Simulation User Manual”, December 3 2010

[5] M. Daigle, M. Foygel and V. Smelyanskiy, “Model-based diagnostics for propellant loading systems”,  2011 IEEE Aerospace Conference, 5-12 March 2011

# License

LH2TS is released under a NASA open source agreement license, version 1.3. For more details see the [LICENSE](LICENSE.md) file.

Modifications in this fork are described in [NOTICE.md](NOTICE.md), as required by clause 3.C of that agreement.

LLNL-CODE-748554
