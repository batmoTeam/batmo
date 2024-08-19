function OCP = computeOCP_NMC111(theta)
    
    coeff1 = [ -4.656   , ...
               0        , ...
               + 88.669 , ...
               0        , ...
               - 401.119, ...
               0        , ...
               + 342.909, ...
               0        , ...
               - 462.471, ...
               0        , ...
               + 433.434];
    
    coeff2 =[ -1      , ...
              0       , ...
              + 18.933, ...
              0       , ...
              - 79.532, ...
              0       , ...
              + 37.311, ...
              0       , ...
              - 73.083, ...
              0       , ...
              + 95.960];
    
    OCP = polyval(coeff1(end:-1:1),theta)./ polyval(coeff2(end:-1:1), theta);
    
end


%{
Copyright 2021-2024 SINTEF Industry, Sustainable Energy Technology
and SINTEF Digital, Mathematics & Cybernetics.

This file is part of The Battery Modeling Toolbox BattMo

BattMo is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

BattMo is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with BattMo.  If not, see <http://www.gnu.org/licenses/>.
%}
