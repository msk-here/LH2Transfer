# refpropm → CoolProp shim: LH2Transfer notes

Replaces the REFPROP dependency in `LLNL/LH2Transfer` (Petitpas 2018,
*IJHE* **43**, 21451–21463) with CoolProp, so the model runs without a
REFPROP licence.

`refpropm.m` is a drop-in replacement for the NIST MATLAB wrapper: same
signature, same units, same quality-flag convention, calling CoolProp's
`PropsSI` underneath. No call site in the model was edited.

The file is **byte-identical** to the copy used in `LH2TransferModel`.
That is deliberate. One implementation serving two codebases is far
easier to defend than two variants that have drifted.

Everything below was checked against the actual source and against
CoolProp numerically. Where something is inference rather than
verification it says so.

Verified with CoolProp 8.0.0, MATLAB R2026a, Python 3.13 (standard
64-bit build, not free-threaded). Re-run `validate_shim.m` after any
CoolProp upgrade.

---

## 1. Call inventory

75 active `refpropm` calls:

| file | active calls |
|---|---|
| `LH2Simulate.m` | 68 (3 more commented out) |
| `inputs_TrailerToDewar.m` | 4 |
| `Data_extraction.m` | 2 |
| `vaporpressure.m` | 1 |
| `runNominal.m` | 0 (all 15 are commented-out diagnostics) |

Every active call passes `'PARAHYD'`. There is no second fluid anywhere
in this repository.

**12 output codes**, all mapped:

| code | meaning | refpropm unit | CoolProp key |
|---|---|---|---|
| `T` | temperature | K | `T` |
| `P` | pressure | **kPa** | `P` (÷1000) |
| `D` | density | kg/m³ | `Dmass` |
| `U` | internal energy | J/kg | `Umass` |
| `H` | enthalpy | J/kg | `Hmass` |
| `Q`/`q` | quality | – | `Q` (see §3) |
| `L` | thermal conductivity | W/(m·K) | `conductivity` |
| `V` | dynamic viscosity | **Pa·s** | `viscosity` |
| `O` | c_v | J/(kg·K) | `Cvmass` |
| `C` | c_p | J/(kg·K) | `Cpmass` |
| `B` | volumetric expansivity | 1/K | `isobaric_expansion_coefficient` |
| `^` | Prandtl number | – | `Prandtl` |

**5 input pairs**: `(T,Q) (T,P) (T,D) (P,U) (D,U)`. All are native
`PropsSI` pairs; no fallback or iterative inversion is needed.

This is a strict subset of what the shim implements, so **the shim
required no modification for this repository**. It additionally supports
`S Y A K M Z` and the `C`/`R`/`M` fixed-point forms, none of which this
model calls.

Unsupported codes raise `refpropm:unsupportedProperty` rather than
returning a default. Add new codes deliberately, after checking both the
NIST `refpropm.m` and the call site.

---

## 2. Unit conventions

Two traps, both handled, both asserted in `validate_shim.m` §2.

**Pressure is kPa.** The model divides by 1000 on input and multiplies by
1e3 on output at every call site. `PropsSI` is Pa. The shim converts in
both directions.

**Viscosity is Pa·s, not µPa·s.** Applying a 1e6 factor here would
inflate every Rayleigh number by 1e6 and produce plausible-looking,
wrong figures. Three confirmations:

1. NIST `refpropm.m` header documents `V   Dynamic viscosity [Pa*s]`,
   and its body returns `{eta*1e-6}` — the DLL gives µPa·s, the wrapper
   converts.
2. `inputs_TrailerToDewar.m:31` and `:39` hardcode
   `mu_L = 13.54e-6` and `mu_v = 0.98e-6`, both labelled `[Pa*s]`.
   Those are the defaults the runtime `refpropm('V',...)` calls
   overwrite, so both must share units.
3. CoolProp at 1 bar gives 1.35458e-5 and 9.87653e-7 Pa·s, matching (2)
   to under 1%.

CoolProp's `viscosity` is already Pa·s, so **no conversion is applied**.

Density comments in the source say `[g/L]`. That is numerically
identical to kg/m³; nothing to convert.

---

## 3. Quality flags

NIST `refpropm.m` lowercases the property request
(`propReq = lower(varargin{1})`), so **`q` and `Q` are the same code**.
Both appear in this repo. For a pure fluid mass quality equals mole
quality, so no basis conversion is needed.

CoolProp returns `10000` for **both** subcooled liquid and superheated
vapour, which makes the value useless for debugging. The shim issues an
explicit `Phase` query and translates to REFPROP's convention:
`-998` subcooled, `998` superheated, `999` supercritical.

Every consumer tests only `quality > 0 && quality < 1`, so the flag value
never changes a branch outcome. It only makes the diagnostics readable.

Three consumers:

| location | protection |
|---|---|
| `LH2Simulate.m:326` (tank 1) | **none** — called inline twice in one `if` |
| `LH2Simulate.m:186` (tank 2, `quality2`) | 3-deep `try`/`catch`; consumed at `:222` and `:391` |
| `LH2Simulate.m:863` (local `vaporpressure`) | same 3-deep `try`/`catch` |

Because the tank-1 call is unprotected, the shim's `Phase` query must
succeed for `(D,U)` or the model dies on the first RHS evaluation.
Verified working for `(D,U)`, `(T,D)` and `(P,U)`.

Note that `LH2Simulate.m:392`, the `refpropm`-based tank-2 branch
condition, is **commented out** upstream; line 391 uses the cached
`quality2` instead.

---

## 4. Reference state — verified, no offset needed

This is the failure mode that would have been silent. The model
integrates internal energy as a state variable, and several hardcoded
fits map `u` directly to density and temperature. A different enthalpy
datum would offset every state and bias every fit at once, while the
figures still looked reasonable.

CoolProp returns **h = 0 and s = 0 exactly** at saturated liquid, normal
boiling point, for `ParaHydrogen`. That is the same NBP anchor REFPROP
9.1 uses. Confirmed independently by the fits themselves: the
`T_L(u)` fit in `Data_extraction.m:31` places `u = 0` at 20.39 K, and
CoolProp puts `u = 0` at 20.42 K — a 0.03 K gap, which is fit residual,
not a datum shift.

Both libraries use the Leachman (2009) parahydrogen EOS, so this is
expected rather than lucky. Asserted in `validate_shim.m` §3.

**No offset correction is applied.** `P.refstatedelta` stays zero.

---

## 5. REFPROP 9.1 cross-check

`inputs_TrailerToDewar.m` records eight constants as "updated using
REFPROP 9.1". Those numbers *are* REFPROP output, which makes them a
genuine cross-check available without a licence. Compared at 1 bar:

| constant | line | REFPROP 9.1 | CoolProp | diff |
|---|---|---|---|---|
| `c_L` [J/kg/K] | 29 | 9702.5 | 9702.49 | +0.000% |
| `kappa_L` [W/m/K] | 30 | 0.10061 | 0.100613 | −0.003% |
| `rho_L` [kg/m³] | 28 | 70.9 | 70.8787 | +0.030% |
| `mu_L` [Pa·s] | 31 | 13.54e-6 | 1.35458e-5 | −0.043% |
| `kappa_v` [W/m/K] | 40 | 0.0166 | 0.0166499 | −0.300% |
| `mu_v` [Pa·s] | 39 | 0.98e-6 | 9.87653e-7 | −0.775% |
| `T_c` [K] | 25 | 32.938 | 32.9378551 | +0.000% |
| `p_c` [Pa] | 26 | 1285822 | 1285776 | +0.002% |

Thermodynamic properties agree to three decimals because the EOS is
shared. Transport properties differ by a few tenths of a percent because
the correlations are implemented separately in each library. Asserted in
`validate_shim.m` §5 with 0.1% and 1% bands respectively.

---

## 6. Hardcoded polynomial fits — the shim does not touch these

The README mentions two REFPROP-derived fits. There are **seven**.
Swapping the property library leaves all of them exactly as they were.

| # | quantity | location | max deviation vs CoolProp |
|---|---|---|---|
| A | ρ_L,sat(T) | `LH2Simulate.m:223` | 1.12% over 20–30 K |
| B | h_vap(T_s) | `LH2Simulate.m:273–274` | 2.81% over 19–30 K |
| C | ρ_L(u) | `LH2Simulate.m:117, 180, 888`; `Data_extraction.m:6, 12` | 0.055% over 20–25 K |
| D | T_L(u) | `Data_extraction.m:31, 46` | 0.051 K over 20–25 K |
| E | T_sat(p in psi) | `inputs_TrailerToDewar.m:57, 67` | 0.11 K at p10/p20 |
| F | T_sat(ρ_v) | `vaporpressure.m:7–9` | 0.498 K over 20–30 K |
| G | p_v(T) | `vaporpressure.m:30` | 1.04% over 20–30 K |

**Decision: keep all seven for the baseline run.** The published figures
were produced with them. Replacing a fit changes the model, not the
property library, and mixing the two changes at once makes any
discrepancy against Petitpas uninterpretable. Replace them later as
separate commits, each with the delta quantified.

Two carry caveats:

- **B degrades to ~7% above 31 K.** The film temperature
  `Ts = T_c·(p/p_c)^(1/5)` reaches 31.5 K at 150 psia, so this matters
  if a run pressurises hard. At the initial pressures it is 19.8 K
  (ST) and 22.9 K (ET), well inside the good range.
- **E collapses near critical**, −14.5 K at 186 psia. It is only
  evaluated at initialisation, where it is +0.08 to +0.11 K, so it is
  safe as used. Do not reuse it elsewhere.

F and G live in the standalone `vaporpressure.m`, which the solver never
reaches (see §7). They affect post-processing only.

---

## 7. Upstream issues in LH2Transfer — not shim concerns

Found while tracing the call sites. None is caused by CoolProp. **Do not
fix any of these before a baseline run exists**, or you will not be
comparing like with like.

**`vaporpressure_bis.m` is missing.** `Data_extraction.m:22` and `:37`
call it; the repository ships nine `.m` files and that is not one of
them. `runNominal.m` calls `Data_extraction` at step 3, so the solve
completes and post-processing then throws. This blocks end-to-end
execution. Its `(u, rho)` signature matches the local subfunction at
`LH2Simulate.m:860`, so it is almost certainly that function extracted
to disk.

**`vaporpressure` is two different functions.** The standalone
`vaporpressure.m` takes `(Tv, rhov)` and uses polynomial fits F and G.
The local subfunction at `LH2Simulate.m:860` takes `(uv, rhov)` and
calls `refpropm`. MATLAB resolves the local one inside `LH2Simulate`, so
the solver never touches the standalone file.

**`LH2Simulate.m:340` uses the wrong tank's temperature.**
`P.kappa_L = refpropm('L','T',TL2(P.nL1),...)` sits in tank 1's block,
where the four surrounding lines all use `TL1(P.nL1)`. The equivalent
line at `:415` in tank 2's block correctly uses `TL2(P.nL2)`. Since
`nL1 == nL2 == 3` the index is valid, so it fails silently. Effect is
small because κ_L varies weakly with temperature.

**`T_c = 32.938` (`inputs_TrailerToDewar.m:25`) is above the true
critical temperature** of 32.9378551 K, by 1.45e-4 K. Any `Q` flash at
`T_c` would throw. It only feeds `Ts0 = T_c·(p/p_c)^(1/λ)`, which stays
subcritical at these pressures, so it does not fire here.
`vaporpressure.m:15–19` contains a hardcoded clamp written to dodge
exactly this. `validate_shim.m` §1 asserts the margin so it cannot
regress unnoticed.

**`LH2Simulate.m:163` divides internal energy by 1.5.** This drops the
state *inside* the two-phase dome (measured q ≈ 0.55–0.63 across
24–28 K), where `(P,U)` is degenerate. Both REFPROP and CoolProp return
T_sat there, so it does not throw — but it means the intermediate vapour
layer temperatures are pinned to saturation. Asserted in
`validate_shim.m` §7.

**Nine `try`/`catch` blocks already exist upstream** (`LH2Simulate.m`
lines 125, 187, 193, 202, 215, 735, 864, 869). They swallow flash
failures and substitute truncated inputs. CoolProp and REFPROP do not
throw under identical conditions, so *which branch runs may differ*.
CoolProp is the more permissive of the two: it returns `Cpmass`,
`conductivity` and `Prandtl` for two-phase `(D,U)` states where the
comment at `LH2Simulate.m:327` says REFPROP fails. Those fallback paths
will simply never fire. If results drift, instrument these before
suspecting the shim.

---

## 8. Performance

Bridge cost is roughly 0.15 ms per call. The ODE right-hand side makes
about 68 calls, so ≈10 ms per RHS evaluation, plus a second Python round
trip for each out-of-dome quality query (the `Phase` lookup). Over a few
thousand evaluations that is a minute or two of bridge overhead.

Set `pyenv(ExecutionMode="InProcess")`. `OutOfProcess` adds a process
boundary to every one of those calls.

`CACHE_ENABLED` at the top of `refpropm.m` stays `false` until a baseline
run is committed. The cache is keyed on full-precision SI inputs, so it
is exact and never interpolates, but correctness comes first. When you
enable it, confirm the headline results are unchanged before keeping it.

One easy optimisation, deliberately **not** applied yet:
`LH2Simulate.m:326` evaluates `refpropm('Q',...)` twice in a single `if`
condition. Caching it in a local, as tank 2 already does with
`quality2`, halves four bridge calls to two per RHS evaluation with no
numerical change. Do it as its own commit, after the baseline.

---

## 9. Relationship to LH2TransferModel

The sibling repo `Albert-Gil/LH2TransferModel` uses the same shim file
with a wider call inventory (15 codes, 8 input pairs, plus one
normal-hydrogen call). Its `SHIM_NOTES.md` documents findings specific
to that codebase — pump isentropic work, Scenario B initialisation,
`MAIN.m` case selection — none of which apply here.

Keep `refpropm.m` synchronised between the two repos. Keep the notes and
the validation harness separate; they are repo-specific by nature.
