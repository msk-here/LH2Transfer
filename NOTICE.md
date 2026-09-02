# Modification Notice

This file is provided in fulfillment of clause 3.C of the NASA Open Source
Agreement version 1.3, under which LH2TS is released.

## Originator

**Muhammad Sami Khan**, GitHub: [@msk-here](https://github.com/msk-here)

These Modifications were produced as part of MSc thesis work on liquid
hydrogen transfer and boil-off modelling.

## Consent

The alterations described below are characterized as a **Modification** as
that term is defined in the NASA Open Source Agreement version 1.3. This
Modification is derived, directly and indirectly, from Original Software
provided by the Government Agency (NASA) and from the Modification entitled
LH2TS (LH2 Transfer Simulation), Copyright © 2018, Lawrence Livermore
National Security, LLC.

Consent is granted to the characterization of these alterations as a
Modification.

## Description of alterations

All alterations were made in **August 2026**. The originating repository is
<https://github.com/LLNL/LH2Transfer>, from which this repository is forked.

### 1. Replaced the REFPROP dependency with CoolProp — 2026-08-28

The Original Software requires a licensed copy of NIST REFPROP 9.1 linked to
MATLAB. This Modification removes that requirement.

**Added `refpropm.m`.** A drop-in reimplementation of the NIST MATLAB wrapper
interface, backed by the open-source CoolProp library via the MATLAB–Python
bridge. It preserves REFPROP's calling signature, unit conventions
(pressure in kPa, viscosity in Pa·s) and quality-flag conventions. **No call
site in the original code was altered.** The Modification covers all 75
active property calls: 12 output codes across 5 input pairs.

**Added `validate_shim.m`.** A validation harness asserting the substitution
is numerically faithful: reference state, unit conventions, thermodynamic
identities, every call shape present in the code, quality branching,
failure behaviour, and the accuracy of the polynomial fits described below.

**Added `SHIM_NOTES.md`.** Documentation of the substitution, including a
cross-check of the eight constants the Original Software records as REFPROP
9.1 output against CoolProp (agreement within 0.03% for thermodynamic
properties and 0.8% for transport properties), and an audit of the seven
hardcoded REFPROP-derived polynomial fits, all of which were **retained
unchanged** so that results remain comparable to those published in
Petitpas (2018).

No governing equation, physical model, parameter or correlation of the
Original Software was altered by this change.

### 2. Added missing file `vaporpressure_bis.m` — 2026-08-29

`Data_extraction.m` lines 22 and 37 call `vaporpressure_bis()`, which is not
present in the LLNL release. Post-processing therefore fails after the ODE
solve completes. This affects the Original Software regardless of which
property library is used.

The file was reconstructed verbatim from the local subfunction at
`LH2Simulate.m:860` and renamed. Its `(u, rho)` signature matches the call
sites, whereas the shipped `vaporpressure.m` takes `(T, rho)` and is a
different function. The body is reproduced unchanged.

### 3. Preallocated output arrays in `Data_extraction.m` — 	2026-08-29

Nine struct fields written inside the post-processing loop were grown one
row at a time, making extraction quadratic in solver output length. At the
observed output size (over 200,000 rows) this took tens of minutes. All
nine fields are written before being read, so the change affects
performance only; no computed value differs.

## Known issues in the Original Software, not altered here

Identified while tracing property call sites, and documented in
`SHIM_NOTES.md`. **These have deliberately been left unchanged**, because
correcting them would change results and prevent comparison against the
published baseline.

- `LH2Simulate.m:340` computes tank 1's liquid thermal conductivity at tank
  2's temperature (`TL2(P.nL1)` where surrounding lines use `TL1(P.nL1)`).
- `inputs_TrailerToDewar.m:25` hardcodes `T_c = 32.938` K, which exceeds the
  true critical temperature of parahydrogen (32.9378551 K).
- `LH2Simulate.m:734` passes `MaxStep` twice within one `odeset` call; the
  second value silently overrides the first.

## Original copyright notice

Copyright © 2018 United States Government as represented by the
Administrator of the National Aeronautics and Space Administration. No
copyright is claimed in the United States under Title 17, U.S. Code. All
Other Rights Reserved.

Modification entitled LH2TS (LH2 Transfer Simulation), Copyright © 2018,
Lawrence Livermore National Security, LLC.

LLNL-CODE-748554

See [LICENSE.md](LICENSE.md) for the full NASA Open Source Agreement v1.3.
