classdef ActiveMaterialInputParams < ComponentInputParams
%
% Input parameter class for :code:`ActiveMaterial` model
% 
    properties
        
        %
        % Input parameter for the  interface :class:`InterfaceInputParams <Electrochemistry.InterfaceInputParams>`
        %
        Interface
        %
        % Input parameter for the solid diffusion model  :class:`SolidDiffusionModelInputParams <Electrochemistry.SolidDiffusionModelInputParams>`
        %
        SolidDiffusion
        
        %% Standard parameters

        electronicConductivity % the electronic conductivity of the material (symbol: sigma)
        density                % the mass density of the material (symbol: rho)
        massFraction           % the ratio of the mass of the material to the total mass of the phase or mixture (symbol: gamma)
        
        thermalConductivity    % the intrinsic Thermal conductivity of the active component
        specificHeatCapacity   % Specific Heat capacity of the active component

        diffusionModelType     % diffusion model type, either 'full' or 'simple'

        %% Advanced parameters

        isRootSimulationModel % Set to true if Active Material is used as a stand-alone model (not within a battery cell, see runActiveMaterial for an example)

        %% Coupling parameters
        
        externalCouplingTerm % structure to describe external coupling (used in absence of current collector)
        
    end

    methods

        function inputparams = ActiveMaterialInputParams(jsonstruct)

            inputparams = inputparams@ComponentInputParams(jsonstruct);
            
            if isempty(inputparams.isRootSimulationModel)
                inputparams.isRootSimulationModel = false;
            end

            sd  = 'SolidDiffusion';
            itf = 'Interface';
            
            pick = @(fd) pickField(jsonstruct, fd);
            
            inputparams.(itf) = InterfaceInputParams(pick('Interface'));

            if isempty(inputparams.diffusionModelType)
                inputparams.diffusionModelType = 'full';
            end

            diffusionModelType = inputparams.diffusionModelType;
            
            switch diffusionModelType
                
              case 'simple'
                
                inputparams.(sd) = SimplifiedSolidDiffusionModelInputParams(pick(sd));
                
              case 'full'

                inputparams.(sd) = FullSolidDiffusionModelInputParams(pick(sd));
                
              otherwise
                
                error('Unknown diffusionModelType %s', diffusionModelType);
                
            end

            inputparams = inputparams.validateInputParams();
            
        end

        function inputparams = validateInputParams(inputparams)


            diffusionModelType = inputparams.diffusionModelType;
            
            sd  = 'SolidDiffusion';
            itf = 'Interface';
            
            inputparams = mergeParameters(inputparams, {{'density'}, {itf, 'density'}});

            if inputparams.isRootSimulationModel
                % only one particle in the stand-alone model
                inputparams.(sd).np = 1;
                % For the standalone model, we set the volume fraction to one (no other component is present)
                inputparams.(sd).volumeFraction = 1;
            end
            
            switch diffusionModelType
                
              case 'simple'
                
                inputparams = mergeParameters(inputparams, {{itf, 'volumetricSurfaceArea'}, {sd, 'volumetricSurfaceArea'}});
                
              case 'full'
                
                inputparams = mergeParameters(inputparams, {{itf, 'volumetricSurfaceArea'}, {sd, 'volumetricSurfaceArea'}});
                
                if ~isempty(inputparams.(sd).diffusionCoefficient)
                    % we impose that cmax in the solid diffusion model and the interface are consistent
                    paramnames = {'saturationConcentration', ...
                                  'guestStoichiometry100', ...
                                  'guestStoichiometry0'};
                    for iparam = 1 : numel(paramnames)
                        paramname = paramnames{iparam};
                        inputparams = mergeParameters(inputparams, {{sd, paramname}, {itf, paramname}}, 'force', false);
                    end
                    
                end

              otherwise
                
                error('Unknown diffusionModelType %s', diffusionModelType);
                
            end

            inputparams = validateInputParams@ComponentInputParams(inputparams);
            
        end
        
    end
    
end


%{
Copyright 2021-2023 SINTEF Industry, Sustainable Energy Technology
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
