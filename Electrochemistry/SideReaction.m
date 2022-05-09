classdef SideReaction < BaseModel

    properties

        % Physical constants
        constants = PhysicalConstants();

        beta = 0.5               % side reaction buttler-volmer  coefficient [-]
        k = 1.36e-12             % side reaction rate constant [m/s]
        conductivity = 5e-6;     % ionic conductivity [S/m]
        
    end

    methods

        function model = SideReaction(paramobj)

            model = model@BaseModel();

             % OBS : All the submodels should have same backend (this is not assigned automaticallly for the moment)
            model.AutoDiffBackend = SparseAutoDiffBackend('useBlocks', false);

            fdnames = {'beta', ...
                       'k'   , ...
                       'conductivity'};

            model = dispatchParams(model, paramobj, fdnames);

        end

        function model = registerVarAndPropfuncNames(model)
            
            %% Declaration of the Dynamical Variables and Function of the model
            % (setup of varnameList and propertyFunctionList)

            model = registerVarAndPropfuncNames@BaseModel(model);
            
            varnames = {};
            % potential in electrode
            varnames{end + 1} = 'phiElectrode';
            % charge carrier concentration in electrode - value at surface
            varnames{end + 1} = 'c';
            % potential in electrolyte
            varnames{end + 1} = 'phiElectrolyte';
            % Reaction rate
            varnames{end + 1} = 'R';
            % overpotential
            varnames{end + 1} = 'eta';
            % Reaction rate coefficient
            varnames{end + 1} = 'j0';
            % External potential drop used in Butler-Volmer
            varnames{end + 1} = 'externalPotentialDrop';
            
            model = model.registerVarNames(varnames);
            
            fn = @SideReaction.updateReactionRate;
            inputnames = {'phiElectrolyte', 'phiElectrode', 'externalPotentialDrop', 'c'};
            model = model.registerPropFunction({'R', fn, inputnames});
            
        end


        function state = updateReactionRate(model, state)

            F = model.constants.F;
            beta = model.beta;
            k = model.k;
            

            T        = state.T;
            c        = state.c;
            phiElyte = state.phiElectrolyte;
            phiElde  = state.phiElectrode;
            dphi     = state.externalPotentialDrop;
            
            eta = (phiElde - phiElyte - dphi);

            %% FIXME : check if volumearea factor should be used, check F factor, check sign
            state.R = -k*c.*exp(-(beta*F)./(R*T).*eta);

        end
        


    end
end

%% References
%   [1] Torchio et al, Journal of The Electrochemical Society, 163 (7)
%   A1192-A1205 (2016), DOI: 10.1149/2.0291607jes



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
