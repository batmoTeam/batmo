classdef CurrentCollectorInputParams < ElectronicComponentInputParams
%
% Input parameter class for the :code:`CurrentCollector` model
%
    properties


        %% Standard parameters

        thermalConductivity  % Thermal conductivity of current collector
        specificHeatCapacity % Heat capacity of current collector
        density              % Density of current collector [kg m^-3]

        %% Advanced parameters

        effectiveVolumetricHeatCapacity % (account for density, if not given computed from specificHeatCapacity)

        %% Coupling term

        externalCouplingTerm % coupling term specification of the current collector with external source


    end

    methods

        function inputparams = CurrentCollectorInputParams(jsonstruct)

            inputparams = inputparams@ElectronicComponentInputParams(jsonstruct);

        end

    end

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
