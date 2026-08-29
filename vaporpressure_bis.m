function pv = vaporpressure_bis(uv,rhov)
%VAPORPRESSURE_BIS  Vapor pressure from internal energy and density.
%
%   pv = vaporpressure_bis(uv, rhov)   returns pressure in Pa.
%
%   PROVENANCE
%   ----------
%   Data_extraction.m lines 22 and 37 call this function, but the LLNL
%   release does not ship it. The body below is the local subfunction
%   at LH2Simulate.m:860 extracted verbatim and renamed.
%
%   The identification is unambiguous:
%     * signature matches -- both take (u, rho), whereas the standalone
%       vaporpressure.m takes (T, rho) and is a different function;
%     * Data_extraction.m:22 passes nominal.uv1(z,end), the last vapor
%       layer, exactly as LH2Simulate.m:131 passes uv1(P.nV1);
%     * it computes the same quantity the solver computes internally.
%
%   The body is reproduced UNCHANGED, including the truncation retries
%   and the redundant fix() in the first catch, so that post-processing
%   reproduces exactly what the solver did. Do not tidy it: any change
%   here changes the model, not the property library.
%
%   Added while porting from REFPROP to CoolProp. Not a shim concern --
%   this file is missing upstream regardless of property library.

% new function for vapor pressure, based on internal energy and density
  try
       quality=refpropm('q','D',rhov,'U',uv,'PARAHYD');
  catch
      uv=fix(100*uv)/100;
      try
          quality=refpropm('q','D',rhov,'U',fix(100*uv)/100,'PARAHYD');
          display('Non-truncation of uv did not converge in "quality". Choosing truncated value instead');
      catch
          quality=refpropm('q','D',fix(100*rhov)/100,'U',fix(100*uv)/100,'PARAHYD');
          rhov=fix(100*rhov)/100;
        %uv=fix(100*uv)/100;
      end
  end
    if quality < 1 && quality >0
         % 2 phase
         temp=refpropm('T','D',rhov,'U',uv,'PARAHYD');
         pv = refpropm('P','T',temp,'Q',1,'PARAHYD')*1e3;% return value in Pa
    else
        %supercricical
        pv = refpropm('P','D',rhov,'U',uv,'PARAHYD')*1e3;% return value in Pa
    end
end

