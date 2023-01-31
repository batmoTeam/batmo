classdef ThermalComponentInputParams < ComponentInputParams

    properties
        
        EffectiveThermalConductivity             % Effective thermal conductivity
        EffectiveVolumetricHeatCapacity
        couplingTerm
        externalHeatTransferCoefficient          % scalar value
        externalHeatTransferCoefficientTopFaces  % scalar value
        externalHeatTransferCoefficientSideFaces % scalar value
        externalTemperature                      % 
        
        useWetProperties % boolean. If set to true, we use wet properties, which means that the thermal properties of the
                         % electrodes and separator are measured with the electrolyte. In this case, the thermal properties of the electrolyte are not needed
    end
    
    methods

        function paramobj = ThermalComponentInputParams(jsonstruct)
            paramobj = paramobj@ComponentInputParams(jsonstruct);
        end
        
    end
    
    
end



%{
Copyright 2021-2022 SINTEF Industry, Sustainable Energy Technology
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
