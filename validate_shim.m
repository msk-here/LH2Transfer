%% validate_shim.m  --  LLNL/LH2Transfer edition
%  Pre-flight check for the CoolProp refpropm shim.
%  Run this BEFORE runNominal.m. If it does not print ALL CHECKS PASSED, do
%  not run the model -- a mis-mapped property code produces figures that
%  look entirely plausible and are wrong.
%
%  Adapted from the LH2TransferModel edition. Differences, and why:
%    * Sections testing 'S' and 'Y' removed: LH2Transfer never calls them,
%      so they exercise shim paths this model cannot reach.
%    * Section [3] is new: asserts the reference state. The model integrates
%      internal energy directly, so a shifted h-datum would bias every state
%      variable and every u-based fit at once, silently.
%    * Section [5] is new: LH2Transfer records six REFPROP 9.1 outputs as
%      hardcoded constants. Those are a real REFPROP cross-check, available
%      without a licence.
%    * Section [7] rewritten to the 33 call shapes that actually appear in
%      this repository.
%    * Section [9] retargeted to this model's initial pressures
%      (14.7 and 30 psia, not 3/5/6 bar).
%    * Section [10] is new: the seven hardcoded polynomial fits are audited
%      against CoolProp. Swapping the property library does not touch them.
%
%  Usage:  >> validate_shim

clear refpropm; clc;
R = struct('name',{},'pass',{},'detail',{});

fprintf('=====================================================\n');
fprintf(' refpropm -> CoolProp shim validation (LH2Transfer)\n');
fprintf('=====================================================\n\n');

PARA    = 'PARAHYD';
psiToPa = 6894.75729;

%% ------------------------------------------------------------------ %%
fprintf('[0] Environment\n');
%% ------------------------------------------------------------------ %%
% MATLAB loads Python LAZILY: pyenv reports Status="NotLoaded" until the
% first py.* call of the session. Force the interpreter up first, THEN
% re-query, otherwise a healthy install looks broken.
try
    pyver  = char(py.sys.version);
    loadOK = true;
catch ME
    pyver  = ME.message;
    loadOK = false;
end
pe = pyenv;
R = tRue(R, 'python bridge loaded', loadOK && pe.Status == "Loaded", ...
    sprintf('Status=%s, Mode=%s, Python=%s', pe.Status, pe.ExecutionMode, strtok(pyver)));

if pe.ExecutionMode ~= "InProcess"
    fprintf(['    WARNING: ExecutionMode is %s. Every property call crosses a\n' ...
             '             process boundary; the ODE right-hand side makes ~60 of\n' ...
             '             them per evaluation. Use pyenv(ExecutionMode="InProcess").\n'], ...
             pe.ExecutionMode);
end

R = tRue(R, 'CoolProp importable', ...
    ~isempty(py.importlib.util.find_spec('CoolProp')), 'py -m pip install CoolProp');
try
    cpver = char(py.CoolProp.CoolProp.get_global_param_string('version'));
catch, cpver = '<unavailable>';
end
fprintf('    CoolProp version: %s\n', cpver);

%% ------------------------------------------------------------------ %%
fprintf('\n[1] Fluid constants queried at runtime\n');
%% ------------------------------------------------------------------ %%
Tcrit   = refpropm('T','C',0,' ',0,PARA);
Pcrit   = refpropm('P','C',0,' ',0,PARA);     % kPa
Dcrit   = refpropm('D','C',0,' ',0,PARA);
Ttriple = refpropm('T','R',0,' ',0,PARA);

R = tEq(R,'Tcrit  [K]',    Tcrit,   32.93785506891549, 1e-9, '');
R = tEq(R,'Pcrit  [kPa]',  Pcrit,   1285.7761785274085,1e-9, 'refpropm returns kPa');
R = tEq(R,'rhocrit[kg/m3]',Dcrit,   31.31543601362373, 1e-9, '');
R = tEq(R,'Ttriple[K]',    Ttriple, 13.8033,           1e-6, '');

% inputs_TrailerToDewar.m:26 hardcodes LH2Model.T_c = 32.938, ABOVE Tcrit.
R = tRue(R,'hardcoded T_c=32.938 is above Tcrit (trap documented)', ...
    32.938 > Tcrit, sprintf('exceeds Tcrit by %.3e K -> any Q-flash at T_c throws', 32.938-Tcrit));

% It only feeds Ts0 = T_c*(p/p_c)^(1/lambda). Confirm that stays subcritical
% at this model's initial pressures.
p_c = 186.49*psiToPa; lambda = 5;
for pPsi = [14.7 30]
    Ts0 = 32.938*((pPsi*psiToPa)/p_c)^(1/lambda);
    R = tRue(R, sprintf('film temp Ts0 at %.1f psia stays subcritical', pPsi), ...
        Ts0 < Tcrit, sprintf('Ts0 = %.3f K', Ts0));
end

%% ------------------------------------------------------------------ %%
fprintf('\n[2] Unit traps (refpropm conventions, NOT CoolProp SI)\n');
%% ------------------------------------------------------------------ %%
Tnbp = refpropm('T','P',101.325,'Q',0,PARA);      % P input in kPa
R = tEq(R,'NBP from P=101.325 kPa [K]', Tnbp, 20.271251, 1e-5, ...
    'validates T output + P INPUT in kPa + Q input together');

Psat = refpropm('P','T',Tnbp,'Q',0,PARA);
R = tEq(R,'P OUTPUT in kPa', Psat, 101.325, 1e-5, ...
    'if this reads ~101325 the Pa->kPa conversion is missing');

muL = refpropm('V','T',Tnbp,'Q',0,PARA);
R = tEq(R,'V OUTPUT in Pa*s', muL, 1.349616e-05, 5e-3, ...
    'if this reads ~13.5 the shim wrongly applied a 1e6 factor');
R = tRue(R,'V magnitude sane for LH2', muL < 1e-3, ...
    sprintf('mu_L = %.6e Pa*s; inputs_TrailerToDewar.m:31 hardcodes 13.54e-6 [Pa*s]', muL));

%% ------------------------------------------------------------------ %%
fprintf('\n[3] Reference state (the model integrates u directly)\n');
%% ------------------------------------------------------------------ %%
% Every hardcoded fit below assumes REFPROP 9.1's reference state. If
% CoolProp anchored h elsewhere, every internal energy in the model would
% be offset and the fits in section [9] would all be biased.
hRef = refpropm('H','P',101.325,'Q',0,PARA);
R = tRue(R,'h = 0 at saturated liquid, NBP', abs(hRef) < 1e-6, ...
    sprintf('h = %.3e J/kg -> NBP reference confirmed, no offset needed', hRef));

%% ------------------------------------------------------------------ %%
fprintf('\n[4] Property-code identities (catch a swapped or mis-scaled code)\n');
%% ------------------------------------------------------------------ %%
% 4a. Prandtl == mu*cp/k. Validates ^, V, C, L simultaneously, and is the
%     single strongest check on the viscosity unit convention.
for T = [21.0, 23.0, 28.0]
    Pr = refpropm('^','T',T,'Q',1,PARA);
    mu = refpropm('V','T',T,'Q',1,PARA);
    cp = refpropm('C','T',T,'Q',1,PARA);
    k  = refpropm('L','T',T,'Q',1,PARA);
    R = tEq(R, sprintf('^ == V*C/L at T=%.0fK (sat vap)',T), Pr, mu*cp/k, 1e-9, ...
        'fails by 1e6 if V is returned in uPa*s');
end

% 4b. U == H - P/rho. Validates U, H, P, D and the kPa->Pa conversion.
Tv = 23.050481; pv_kPa = 30*psiToPa/1000;          % the model's ET initial state
h = refpropm('H','T',Tv,'P',pv_kPa,PARA);
d = refpropm('D','T',Tv,'P',pv_kPa,PARA);
u = refpropm('U','T',Tv,'P',pv_kPa,PARA);
R = tEq(R,'U == H - P/rho (P in kPa -> *1000)', u, h - (pv_kPa*1000)/d, 1e-8, ...
    'off by 1000x if the pressure unit is wrong');

% 4c. C is cp and O is cv, not the other way round.
cp = refpropm('C','T',23,'Q',1,PARA);
cv = refpropm('O','T',23,'Q',1,PARA);
R = tRue(R,'C (cp) > O (cv)', cp > cv, sprintf('cp=%.1f cv=%.1f', cp, cv));
gam = refpropm('C','T',40,'P',1,PARA) / refpropm('O','T',40,'P',1,PARA);
R = tEq(R,'C/O -> 5/3 in dilute limit', gam, 5/3, 5e-3, ...
    'para-H2 has frozen rotation at low T; inputs_*.m:38 sets gamma_=5/3');

% 4d. B is volumetric expansivity [1/K]: beta -> 1/T for a dilute gas.
b80 = refpropm('B','T',80,'P',10,PARA);
R = tEq(R,'B -> 1/T in dilute limit', b80*80, 1.0, 5e-3, ...
    'if B were cp or cv this is off by many orders of magnitude');
bL = refpropm('B','T',21,'Q',0,PARA);
R = tRue(R,'B for sat liquid is small and positive', bL > 0 && bL < 1, ...
    sprintf('beta_L(21K) = %.6f 1/K (feeds the Rayleigh numbers)', bL));

% 4e. Round-trip consistency across the input pairs this model uses.
rho = refpropm('D','T',Tv,'P',pv_kPa,PARA);
uu  = refpropm('U','T',Tv,'D',rho,PARA);
R = tEq(R,'T round-trip via (D,U)', refpropm('T','D',rho,'U',uu,PARA), Tv, 1e-7, ...
    'LH2Simulate.m:124');
R = tEq(R,'P round-trip via (D,U)', refpropm('P','D',rho,'U',uu,PARA), pv_kPa, 1e-7, ...
    'LH2Simulate.m:881');
R = tEq(R,'D round-trip via (P,U)', refpropm('D','P',pv_kPa,'U',uu,PARA), rho, 1e-7, ...
    'LH2Simulate.m:605');

%% ------------------------------------------------------------------ %%
fprintf('\n[5] Cross-check against REFPROP 9.1 values recorded in the repo\n');
%% ------------------------------------------------------------------ %%
% inputs_TrailerToDewar.m records six properties as "updated using REFPROP
% 9.1 @ 1 bar". Those numbers ARE REFPROP output. Comparing them to CoolProp
% is the closest thing to a REFPROP cross-check available without a licence.
% Thermodynamic properties share the Leachman EOS and should agree to ~0.1%;
% transport correlations differ slightly between the two libraries, so 1%.
p1bar = 100;                                        % kPa
ref = { ...
 'rho_L  [kg/m3]',  70.9,      refpropm('D','P',p1bar,'Q',0,PARA), 1e-3; ...
 'c_L    [J/kg/K]', 9702.5,    refpropm('C','P',p1bar,'Q',0,PARA), 1e-3; ...
 'kappa_L[W/m/K]',  0.10061,   refpropm('L','P',p1bar,'Q',0,PARA), 1e-2; ...
 'mu_L   [Pa*s]',   13.54e-6,  refpropm('V','P',p1bar,'Q',0,PARA), 1e-2; ...
 'kappa_v[W/m/K]',  0.0166,    refpropm('L','P',p1bar,'Q',1,PARA), 1e-2; ...
 'mu_v   [Pa*s]',   0.98e-6,   refpropm('V','P',p1bar,'Q',1,PARA), 1e-2; ...
 'T_c    [K]',      32.938,    Tcrit,                              1e-3; ...
 'p_c    [kPa]',    186.49*psiToPa/1000, Pcrit,                    1e-3};
for i = 1:size(ref,1)
    repoVal = ref{i,2}; cpVal = ref{i,3}; tol = ref{i,4};
    rel = abs(repoVal-cpVal)/abs(cpVal);
    R = tRue(R, sprintf('REFPROP 9.1 %s', ref{i,1}), rel <= tol, ...
        sprintf('repo=%.6g CoolProp=%.6g  diff=%+.3f%%', repoVal, cpVal, 100*rel*sign(repoVal-cpVal)));
end

%% ------------------------------------------------------------------ %%
fprintf('\n[6] Quality: branching must match the model''s (q>0 && q<1) test\n');
%% ------------------------------------------------------------------ %%
% Three consumers branch on quality:
%   LH2Simulate.m:326  tank 1 -- called inline TWICE, NO try/catch
%   LH2Simulate.m:186  tank 2 -- sets quality2 inside a 3-deep try/catch,
%                      consumed at :222 and :391
%   LH2Simulate.m:863  local vaporpressure subfunction, same try/catch
% Only the tank-1 call is unprotected, so a failure there is a hard crash.
d2 = refpropm('D','T',22,'Q',0.5,PARA);
u2 = refpropm('U','T',22,'Q',0.5,PARA);
q2 = refpropm('q','D',d2,'U',u2,PARA);
R = tEq(R,'two-phase q recovered', q2, 0.5, 1e-6, '');
R = tRue(R,'two-phase takes the SATURATED branch', q2 > 0 && q2 < 1, sprintf('q = %.6f', q2));

qv = refpropm('q','D',rho,'U',uu,PARA);
R = tRue(R,'superheated vapour takes the D,U branch', ~(qv > 0 && qv < 1), ...
    sprintf('q flag = %g (REFPROP uses 998)', qv));

dl = refpropm('D','T',20.4,'Q',0,PARA);
ul = refpropm('U','T',20.4,'Q',0,PARA);
ql = refpropm('q','D',dl,'U',ul,PARA);
R = tRue(R,'saturated liquid takes the D,U branch', ~(ql > 0 && ql < 1), ...
    sprintf('q flag = %g', ql));

R = tEq(R,'''q'' and ''Q'' are the same code', ...
    refpropm('Q','D',rho,'U',uu,PARA), qv, 0, ...
    'NIST refpropm.m line 328: propReq = lower(varargin{1})');

%% ------------------------------------------------------------------ %%
fprintf('\n[7] Every call shape that appears in LH2Transfer\n');
%% ------------------------------------------------------------------ %%
% Enumerated from LH2Simulate.m, inputs_TrailerToDewar.m, Data_extraction.m
% and vaporpressure.m. 12 output codes x 5 input pairs, as actually used.
S = { ...
 'B','T',Tv,'Q',1,PARA;      'B','T',20.4,'Q',0,PARA;   'B','D',rho,'U',uu,PARA; ...
 'C','T',Tv,'Q',1,PARA;      'C','T',20.4,'Q',0,PARA;   'C','D',rho,'U',uu,PARA; ...
 'D','T',20.4,'Q',0,PARA;    'D','T',Tv,'P',pv_kPa,PARA;'D','P',pv_kPa,'U',uu,PARA; ...
 'H','T',20.4,'Q',0,PARA;    'H','T',Tv,'Q',1,PARA;     'H','T',Tv,'D',rho,PARA; ...
 'L','T',Tv,'Q',1,PARA;      'L','T',20.4,'Q',0,PARA;   'L','D',rho,'U',uu,PARA; ...
 'O','T',Tv,'Q',1,PARA;      'O','T',20.4,'Q',0,PARA;   'O','D',rho,'U',uu,PARA; ...
 'P','T',Tv,'Q',1,PARA;      'P','D',rho,'U',uu,PARA; ...
 'Q','D',rho,'U',uu,PARA;    'q','D',d2,'U',u2,PARA; ...
 'T','D',rho,'U',uu,PARA;    'T','P',pv_kPa,'U',uu,PARA; ...
 'U','T',20.4,'Q',0,PARA;    'U','T',Tv,'Q',1,PARA;     'U','T',Tv,'D',rho,PARA; ...
 'V','T',Tv,'Q',1,PARA;      'V','T',20.4,'Q',0,PARA;   'V','D',rho,'U',uu,PARA; ...
 '^','T',Tv,'Q',1,PARA;      '^','T',20.4,'Q',0,PARA;   '^','D',rho,'U',uu,PARA; ...
 };
nbad = 0;
for i = 1:size(S,1)
    try
        v = refpropm(S{i,1},S{i,2},S{i,3},S{i,4},S{i,5},S{i,6});
        if ~isfinite(v), error('non-finite'); end
    catch ME
        nbad = nbad + 1;
        fprintf('    !! %s(%s,%s) -> %s\n', S{i,1},S{i,2},S{i,4}, ME.message);
    end
end
R = tRue(R, sprintf('all %d repo call shapes evaluate', size(S,1)), nbad==0, ...
    sprintf('%d failed', nbad));

% LH2Simulate.m:163 divides internal energy by 1.5, which drops the state
% INSIDE the dome where (P,U) is degenerate. REFPROP returns Tsat there and
% so must the shim, or the vapour layer temperatures go wrong.
uSat = refpropm('U','T',26,'Q',1,PARA);
pSat = refpropm('P','T',26,'Q',1,PARA);
Thack = refpropm('T','P',pSat,'U',uSat/1.5,PARA);
R = tEq(R,'(P,U) inside dome returns Tsat [LH2Simulate.m:163]', Thack, 26.0, 1e-6, ...
    sprintf('u/1.5 lands at q=%.3f', refpropm('q','P',pSat,'U',uSat/1.5,PARA)));

%% ------------------------------------------------------------------ %%
fprintf('\n[8] Loud failure (no silent fallbacks)\n');
%% ------------------------------------------------------------------ %%
R = tRue(R,'unsupported property code throws', ...
    throwsFor(@() refpropm('W','T',21,'Q',0,PARA)), 'must not return a default');
R = tRue(R,'unsupported input spec throws', ...
    throwsFor(@() refpropm('D','A',21,'Q',0,PARA)), '');
R = tRue(R,'unknown fluid throws', ...
    throwsFor(@() refpropm('D','T',21,'Q',0,'PARAHYDROGEN_TYPO')), '');
R = tRue(R,'impossible state throws', ...
    throwsFor(@() refpropm('D','T',Tcrit+50,'Q',0,PARA)), 'Q-flash above Tcrit');

%% ------------------------------------------------------------------ %%
fprintf('\n[9] Initial conditions: is the ullage vapour or liquid?\n');
%% ------------------------------------------------------------------ %%
% inputs_TrailerToDewar.m:57,67 set Tv0 from a Tsat(p) fit plus 0.1 K.
% If that landed below Tsat the "vapour" would initialise as liquid and the
% ullage mass balance would be nonsense.
Tv0 = @(p) 0.1+(-1.603941638811E-11*(p/psiToPa)^6 + 7.830478134841E-09*(p/psiToPa)^5 ...
    -1.549372675881E-06*(p/psiToPa)^4 + 1.614567978153E-04*(p/psiToPa)^3 ...
    -9.861776990784E-03*(p/psiToPa)^2 + 4.314905904166E-01*(p/psiToPa) + 1.559843335080E+01);
for pPsi = [14.7 30]                      % p10 (ST) and p20 (ET)
    p    = pPsi*psiToPa;
    Tsat = refpropm('T','P',p/1000,'Q',0,PARA);
    T0   = Tv0(p);
    rv   = refpropm('D','T',T0,'P',p/1000,PARA);
    R = tRue(R, sprintf('ullage at %.1f psia initialises SUPERHEATED', pPsi), ...
        T0 > Tsat && rv < 20, ...
        sprintf('Tsat=%.3f K, code uses Tv0=%.3f K (+%.3f K), rho_v=%.3f kg/m3', ...
                Tsat, T0, T0-Tsat, rv));
end

%% ------------------------------------------------------------------ %%
fprintf('\n[10] Hardcoded polynomial fits vs CoolProp (NOT fixed by the shim)\n');
%% ------------------------------------------------------------------ %%
% Seven fits derived from REFPROP 9.1 are baked into the source. Swapping
% the property library leaves them untouched. These are reported, not
% "corrected" -- the published figures were produced WITH them.

% [A] saturated liquid density vs T -- LH2Simulate.m:223
Ts = 20:1:30; e = zeros(size(Ts));
for i=1:numel(Ts)
    T=Ts(i);
    fit = -5.24588E-05*T^6 + 7.39502E-03*T^5 - 4.29976E-01*T^4 + 1.31922E+01*T^3 ...
          - 2.25208E+02*T^2 + 2.02705E+03*T - 7.43508E+03;
    e(i) = 100*(fit - refpropm('D','T',T,'Q',0,PARA))/refpropm('D','T',T,'Q',0,PARA);
end
R = tBand(R,'[A] rho_Lsat(T)   LH2Simulate.m:223', max(abs(e)), 2.0, '%', '20-30 K');

% [B] enthalpy of vaporisation vs film T -- LH2Simulate.m:273-274
Ts = 19:1:30; e = zeros(size(Ts));
for i=1:numel(Ts)
    T=Ts(i);
    fit = 1000*(-0.002445451720487*T^6 + 0.3629946692976*T^5 - 22.28028769483*T^4 ...
          + 723.6541112107*T^3 - 13116.31006512*T^2 + 125780.2915522*T - 498095.5392318);
    cpv = refpropm('H','T',T,'Q',1,PARA) - refpropm('H','T',T,'Q',0,PARA);
    e(i) = 100*(fit - cpv)/cpv;
end
R = tBand(R,'[B] h_vap(Ts)     LH2Simulate.m:273', max(abs(e)), 3.0, '%', '19-30 K');
fprintf('        NOTE: [B] degrades to ~7%% above 31 K. Film temp reaches 31.5 K\n');
fprintf('              at 150 psia, so watch this if the run pressurises hard.\n');

% [C] saturated liquid density vs u -- LH2Simulate.m:888, Data_extraction.m:6,12
% [D] liquid temperature vs u      -- Data_extraction.m:31,46
Ts = 20:1:25; eC = zeros(size(Ts)); eD = zeros(size(Ts));
for i=1:numel(Ts)
    T  = Ts(i);
    uk = refpropm('U','T',T,'Q',0,PARA)/1000;
    rC = -5.12074746E-07*uk^3 - 1.56628367E-05*uk^2 - 1.18436797E-01*uk + 7.06218354E+01;
    tD = -0.0002041552*uk^2 + 0.1010598604*uk + 20.3899281428;
    eC(i) = 100*(rC - refpropm('D','T',T,'Q',0,PARA))/refpropm('D','T',T,'Q',0,PARA);
    eD(i) = tD - T;
end
R = tBand(R,'[C] rho_L(u)      LH2Simulate.m:888', max(abs(eC)), 0.5, '%', '20-25 K');
R = tBand(R,'[D] T_L(u)        Data_extraction.m:31', max(abs(eD)), 0.1, 'K', '20-25 K');

% [E] Tsat(p) in psi -- inputs_TrailerToDewar.m:57,67 (initialisation only)
e = zeros(1,2); pv = [14.7 30];
for i=1:2
    e(i) = (Tv0(pv(i)*psiToPa) - 0.1) - refpropm('T','P',pv(i)*psiToPa/1000,'Q',0,PARA);
end
R = tBand(R,'[E] Tsat(p_psi)   inputs_*.m:57,67', max(abs(e)), 0.1, 'K', 'at p10,p20');
fprintf('        NOTE: [E] is only used at initialisation. It breaks down badly\n');
fprintf('              near critical (-14.5 K at 186 psia). Do not reuse it.\n');

% [F] Tsat(rho_v) and [G] p_v(T) -- vaporpressure.m:7-9 and :30
% Only reached by the STANDALONE vaporpressure.m. The solver uses the local
% subfunction at LH2Simulate.m:860, which calls refpropm instead.
Ts = 20:1:30; eF = zeros(size(Ts)); eG = zeros(size(Ts));
for i=1:numel(Ts)
    T = Ts(i); dV = refpropm('D','T',T,'Q',1,PARA); pT = refpropm('P','T',T,'Q',1,PARA)*1000;
    tF = -3.9389254667e-09*dV^6 + 1.0053641879e-06*dV^5 - 1.0304184083e-04*dV^4 ...
         + 5.3058942923e-03*dV^3 - 1.4792439609e-01*dV^2 + 2.2234419496*dV + 1.7950995359e+01;
    pG = (1.6133821043e-1*T^3 - 6.9432088540*T^2 + 1.1373052580e2*T - 6.9558797798e2)*1e3;
    eF(i) = tF - T;
    eG(i) = 100*(pG - pT)/pT;
end
R = tBand(R,'[F] Tsat(rho_v)   vaporpressure.m:7', max(abs(eF)), 0.6, 'K', '20-30 K');
R = tBand(R,'[G] p_v(T)        vaporpressure.m:30', max(abs(eG)), 1.5, '%', '20-30 K');

%% ------------------------------------------------------------------ %%
%% Summary
%% ------------------------------------------------------------------ %%
np = sum([R.pass]); nt = numel(R);
fprintf('\n=====================================================\n');
if np == nt
    fprintf(' ALL CHECKS PASSED  (%d/%d)  -- safe to run runNominal.m\n', np, nt);
else
    fprintf(' %d of %d CHECKS FAILED -- DO NOT RUN THE MODEL\n', nt-np, nt);
    for i = 1:nt
        if ~R(i).pass, fprintf('   FAILED: %s   [%s]\n', R(i).name, R(i).detail); end
    end
end
fprintf('=====================================================\n');


%% ==================== helpers ==================== %%
function R = tEq(R, name, actual, expected, reltol, why)
if expected == 0
    ok = abs(actual) <= reltol;
    err = abs(actual);
else
    err = abs(actual-expected)/abs(expected);
    ok = err <= reltol;
end
R(end+1) = struct('name',name,'pass',ok, ...
    'detail',sprintf('got %.10g expected %.10g relerr %.2e', actual, expected, err));
fprintf('    [%s] %-42s %14.8g   %s\n', tick(ok), name, actual, why);
end

function R = tRue(R, name, cond, detail)
cond = logical(cond);
R(end+1) = struct('name',name,'pass',cond,'detail',detail);
fprintf('    [%s] %-42s %s\n', tick(cond), name, detail);
end

function R = tBand(R, name, maxerr, tol, unit, range)
ok = maxerr <= tol;
R(end+1) = struct('name',name,'pass',ok, ...
    'detail',sprintf('max deviation %.4g %s over %s (band %.4g %s)', maxerr, unit, range, tol, unit));
fprintf('    [%s] %-42s max %8.4g %-2s over %-9s (band %g)\n', ...
    tick(ok), name, maxerr, unit, range, tol);
end

function s = tick(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function tf = throwsFor(fh)
try
    fh(); tf = false;
catch
    tf = true;
end
end
