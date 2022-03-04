classdef BareBattery < BaseModel
% 
% The battery model consists of 
%
% * an Electrolyte model given in :attr:`Electrolyte` property
% * a Negative Electrode Model given in :attr:`NegativeElectrode` property
% * a Positive Electrode Model given in :attr:`PositiveElectrode` property
% * a Thermal model given in :attr:`ThermalModel` property
%
    properties
        
        con = PhysicalConstants();

        Electrolyte       % Electrolyte model, instance of :class:`Electrolyte <Electrochemistry.Electrodes.Electrolyte>`
        NegativeElectrode % Negative Electrode Model, instance of :class:`Electrode <Electrochemistry.Electrodes.Electrode>`
        PositiveElectrode % Positive Electrode Model, instance of :class:`Electrode <Electrochemistry.Electrodes.Electrode>`
        
        initT % Initial temperature
        
        couplingTerms % Coupling terms
        cmin % mininum concentration used in capping

        couplingNames 
        
        mappings
        
        
    end
    
    methods
        
        function model = BareBattery(paramobj)

            model = model@BaseModel();
            
            % All the submodels should have same backend (this is not assigned automaticallly for the moment)
            model.AutoDiffBackend = SparseAutoDiffBackend('useBlocks', false);
            
            %% Setup the model using the input parameters
            fdnames = {'G'             , ...
                       'couplingTerms' , ...
                       'initT'};
            
            model = dispatchParams(model, paramobj, fdnames);
            
            % Assign the components : Electrolyte, NegativeElectrode, PositiveElectrode
            model.NegativeElectrode = model.setupElectrode(paramobj.NegativeElectrode);
            model.PositiveElectrode = model.setupElectrode(paramobj.PositiveElectrode);
            model.Electrolyte = model.setupElectrolyte(paramobj.Electrolyte);

            % defines shortcuts
            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            itf   = 'Interface';
            sd    = 'SolidDiffusion';
            
            % setup Electrolyte model (setup electrolyte volume fractions in the different regions)
            model = model.setupElectrolyteModel();            
            
            % setup couplingNames
            model.couplingNames = cellfun(@(x) x.name, model.couplingTerms, 'uniformoutput', false);
            
            % setup some mappings (mappings from electrodes to electrolyte)
            model = model.setupMappings();
            
            % setup capping
            cmax_ne = model.(ne).(itf).cmax;
            cmax_pe = model.(pe).(itf).cmax;
            model.cmin = 1e-5*max(cmax_ne, cmax_pe);

        end

        function model = setupVarPropNames(model)

            itf = 'Interface';
            sd = 'SolidDiffusion';
            
            %% Declaration of the Dynamical Variables and Function of the model
            % (setup of varnameList and propertyFunctionList)

            %% Declaration of the Dynamical Variables and Function of the model
            % (setup of varnameList and propertyFunctionList)
            
            model = model.registerSubModels({'Electrolyte'       , ...
                                             'NegativeElectrode' , ...
                                             'PositiveElectrode'});
                        
            varnames = {'SOC', ...
                        'T', ...
                        'controlEq'};
            
            model = model.registerVarNames(varnames);
            
            % function that dispatch the temperatures in the submodels
            fn = @Battery.updateTemperature;
            model = model.registerPropFunction({{ne, 'T'}      , fn, {'T'}});
            model = model.registerPropFunction({{ne, itf, 'T'} , fn, {'T'}});
            model = model.registerPropFunction({{ne, sd,  'T'} , fn, {'T'}});
            model = model.registerPropFunction({{pe, 'T'}      , fn, {'T'}});
            model = model.registerPropFunction({{pe, itf, 'T'} , fn, {'T'}});
            model = model.registerPropFunction({{pe, sd,  'T'} , fn, {'T'}});
            model = model.registerPropFunction({{elyte, 'T'}   , fn, {'T'}});
           
            % function that setups the couplings
            
            fn = @Battery.updateElectrodeCoupling;
            
            inputnames = {{elyte, 'c'}, ...
                          {elyte, 'phi'}};
            model = model.registerPropFunction({{ne, itf, 'phiElectrolyte'}, fn, inputnames});
            model = model.registerPropFunction({{ne, itf, 'cElectrolyte'}  , fn, inputnames});
            model = model.registerPropFunction({{pe, itf, 'phiElectrolyte'}, fn, inputnames});
            model = model.registerPropFunction({{pe, itf, 'cElectrolyte'}  , fn, inputnames});
            
            fn = @Battery.updateElectrolyteCoupling;
            
            inputnames = {{ne, itf, 'R'}, ...
                          {pe, itf, 'R'}};
            model = model.registerPropFunction({{elyte, 'massSource'}, fn, inputnames});
            model = model.registerPropFunction({{elyte, 'eSource'}   , fn, inputnames});
            
            fn = @Battery.setupExternalCouplingNegativeElectrode;
            model = model.registerPropFunction({{ne, 'jBcSource'}, fn, {'phi'}});
            
            fn = @Battery.setupExternalCouplingPositiveElectrode;
            model = model.registerPropFunction({{pe, 'jBcSource'}, fn, {'phi', 'E'}});
            
            %% setup control equation
            fn = @Batter.setupEIEquation;
            inputnames = {{pe, 'E'}, ...
                          {pe, 'I'}, ...
                          {pe, 'phi'}};
            model = model.registerPropFunction({'controlEq', fn, inputnames});
            
        end
            
        function electrode = setupElectrode(model, paramobj)
        % Setup the electrode models (both :attr:`NegativeElectrode` and :attr:`PositiveElectrode`). Here, :code:`paramobj`
        % is instance of :class:`ElectrodeInputParams <Electrochemistry.Electrodes.ElectrodeInputParams>`
        %
        % Parameters:
        %    paramobj: input parameter structure
        %
        % Returns:
        %    electrode object

            electrode = ActiveMaterial(paramobj);
            
        end
        
        function electrolyte = setupElectrolyte(model, paramobj)
        % Setup the electrolyte model :attr:`Electrolyte`. Here, :code:`paramobj` is instance of
        % :class:`ElectrolyteInputParams <Electrochemistry.ElectrolyteInputParams>`
            switch paramobj.electrolyteType
              case 'binary'
                electrolyte = Electrolyte(paramobj);
              otherwise
                % binary is default
                electrolyte = Electrolyte(paramobj)
            end
        end
        
        function model = setupMappings(model)

            ne      = 'NegativeElectrode';
            pe      = 'PositiveElectrode';
            elyte   = 'Electrolyte';
            
            G_elyte = model.(elyte).G;
            elytecelltbl.cells = (1 : G_elyte.cells.num)';
            elytecelltbl.globalcells = G_elyte.mappings.cellmap;
            elytecelltbl = IndexArray(elytecelltbl);

            eldes = {ne, pe};

            for ind = 1 : numel(eldes)

                elde = eldes{ind};
                G_elde  = model.(elde).G;
                clear eldecelltbl;
                eldecelltbl.cells = (1 : G_elde.cells.num)';
                eldecelltbl.globalcells = G_elde.mappings.cellmap;
                eldecelltbl = IndexArray(eldecelltbl);
                
                map = TensorMap();
                map.fromTbl = elytecelltbl;
                map.toTbl = eldecelltbl;
                map.replaceFromTblfds = {{'cells', 'elytecells'}};
                map.replaceToTblfds = {{'cells', 'eldecells'}};
                map.mergefds = {'globalcells'};
                
                mappings.(elde) = map.getDispatchInd();
                
            end
            
            model.mappings = mappings;
            
        end
        
        function model = setupElectrolyteModel(model)
        % Assign the electrolyte volume fractions in the different regions

            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            sep   = 'Separator';

            elyte_cells = zeros(model.G.cells.num, 1);
            elyte_cells(model.(elyte).G.mappings.cellmap) = (1 : model.(elyte).G.cells.num)';

            model.(elyte).volumeFraction = NaN(model.(elyte).G.cells.num, 1);
            model.(elyte).volumeFraction(elyte_cells(model.(ne).G.mappings.cellmap))  = model.(ne).porosity;
            model.(elyte).volumeFraction(elyte_cells(model.(pe).G.mappings.cellmap))  = model.(pe).porosity;
            model.(elyte).volumeFraction(elyte_cells(model.(elyte).(sep).G.mappings.cellmap)) = model.(elyte).(sep).porosity;

        end
        
        function initstate = setupInitialState(model)
        % Setup the initial state

            nc = model.G.cells.num;

            SOC = model.SOC;
            T   = model.initT;
            
            initstate.SOC = SOC*ones(nc, 1);
            initstate.T = T*ones(nc, 1);
            
            bat = model;
            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            am    = 'ActiveMaterial';
                        
            %% synchronize temperatures
            initstate = model.updateTemperature(initstate);
            
            %% setup initial NegativeElectrode state
            
            % shortcut
            % negAm : ActiveMaterial of the negative electrode
            
            negAm = bat.(ne).(am); 
            
            m = (1 ./ (negAm.theta100 - negAm.theta0));
            b = -m .* negAm.theta0;
            theta = (SOC - b) ./ m;
            c = theta .* negAm.Li.cmax;
            c = c*ones(negAm.G.cells.num, 1);

            initstate.(ne).c = c;
            % We bypass the solid diffusion equation to set directly the particle surface concentration (this is a bit hacky)
            initstate.(ne).(am).cElectrode = c;
            initstate.(ne).(am) = negAm.updateOCP(initstate.(ne).(am));

            OCP = initstate.(ne).(am).OCP;
            ref = OCP(1);
            
            initstate.(ne).phi = OCP - ref;

            %% setup initial PositiveElectrode state

            % shortcut
            % posAm : ActiveMaterial of the positive electrode
            
            posAm = bat.(pe).(am);
            
            m = (1 ./ (posAm.theta100 - posAm.theta0));
            b = -m .* posAm.theta0;
            theta = (SOC - b) ./ m;
            c = theta .* posAm.Li.cmax;
            c = c*ones(posAm.G.cells.num, 1);

            initstate.(pe).c = c;
            % We bypass the solid diffusion equation to set directly the particle surface concentration (this is a bit hacky)
            initstate.(pe).(am).cElectrode = c;
            initstate.(pe).(am) = posAm.updateOCP(initstate.(pe).(am));
            
            OCP = initstate.(pe).(am).OCP;
            initstate.(pe).phi = OCP - ref;

            %% setup initial Electrolyte state

            initstate.(elyte).phi = zeros(bat.(elyte).G.cells.num, 1) - ref;
            cs = cell(2,1);
            initstate.(elyte).cs = cs;
            initstate.(elyte).cs{1} = 1000*ones(bat.(elyte).G.cells.num, 1);

            %% setup initial Current collectors state

            initstate.(pe).E = OCP(1) - ref;
            initstate.(pe).I = 0;
            
        end
        
        function [problem, state] = getEquations(model, state0, state,dt, drivingForces, varargin)
        % Assembly of the governing equation
            opts = struct('ResOnly', false, 'iteration', 0); 
            opts = merge_options(opts, varargin{:});
            
            time = state0.time + dt;
            if(not(opts.ResOnly))
                state = model.initStateAD(state);
            end
            
            T = model.initT;
            nc = model.G.cells.num;
            state.T = T*ones(nc, 1);
            
            %% for now temperature and SOC are kept constant
            nc = model.G.cells.num;
            
            % Shortcuts used in this function
            battery = model;
            ne      = 'NegativeElectrode';
            pe      = 'PositiveElectrode';
            elyte   = 'Electrolyte';
            am      = 'ActiveMaterial';
            itf     = 'Interface';
            sd      = 'SolidDiffusion';
            
            electrodes = {ne, pe};

            %% Synchronization across components

            % temperature
            state = battery.updateTemperature(state);

            state.(elyte) = battery.(elyte).updateConcentrations(state.(elyte));
            
            for ind = 1 : numel(electrodes)
                elde = electrodes{ind};
                % dispatch potential and concentration from electode active component to submodels
                state.(elde) = battery.(elde).updatePhi(state.(elde));
            end
            
            %% Accumulation terms

            state = battery.updateAccumTerms(state, state0, dt);

            %% Update Electrolyte -> Electrodes coupling 
            
            state = battery.updateElectrodeCoupling(state); 

            %% Update reaction rates in both electrodes

            for ind = 1 : numel(electrodes)
                elde = electrodes{ind};
                state.(elde) = battery.(elde).updateSolidConcentrations(state.(elde));
                state.(elde).(itf) = battery.(elde).(itf).updateReactionRateCoefficient(state.(elde).(itf));
                state.(elde).(itf) = battery.(elde).(itf).updateOCP(state.(elde).(itf));
                state.(elde).(itf) = battery.(elde).(itf).updateReactionRate(state.(elde).(itf));
            end

            %% Update Electrodes -> Electrolyte  coupling

            state = battery.updateElectrolyteCoupling(state);
            
            %% Update  external coupling
            
            state = model.setupExternalCouplingNegativeElectrode(state);
            state = model.setupExternalCouplingPositiveElectrode(state);
            
            %% elyte charge conservation

            state.(elyte) = battery.(elyte).updateCurrentBcSource(state.(elyte));
            state.(elyte) = battery.(elyte).updateConductivity(state.(elyte));
            state.(elyte) = battery.(elyte).updateChemicalCurrent(state.(elyte));
            state.(elyte) = battery.(elyte).updateCurrent(state.(elyte));
            state.(elyte) = battery.(elyte).updateChargeConservation(state.(elyte));

            %% Electrodes charge conservation - Active material part

            for ind = 1 : numel(electrodes)
                elde = electrodes{ind};
                state.(elde) = battery.(elde).updateCurrentSource(state.(elde));
                state.(elde) = battery.(elde).updateCurrent(state.(elde));
                state.(elde) = battery.(elde).updateChargeConservation(state.(elde));
            end
            
            %% elyte mass conservation

            state.(elyte) = battery.(elyte).updateDiffusionCoefficient(state.(elyte));
            state.(elyte) = battery.(elyte).updateMassFlux(state.(elyte));
            state.(elyte) = battery.(elyte).updateMassConservation(state.(elyte));

            %% update solid diffustion mass conservation equations
            for ind = 1 : numel(electrodes)
                elde = electrodes{ind};
                state.(elde) = battery.(elde).dispatchSolidRate(state.(elde));
                state.(elde).(sd) = battery.(elde).(sd).updateDiffusionCoefficient(state.(elde).(sd));
                if model.(elde).useSimplifiedDiffusionModel
                    state.(elde) = battery.(elde).assembleAccumTerm(state.(elde), state0.(elde), dt);
                    state.(elde) = battery.(elde).updateMassSource(state.(elde));
                    state.(elde) = battery.(elde).updateMassConservation(state.(elde));
                    state.(elde).(sd) = battery.(elde).(sd).assembleSolidDiffusionEquation(state.(elde).(sd));
                else
                    state.(elde).(sd) = battery.(elde).(sd).updateMassSource(state.(elde).(sd));
                    state.(elde).(sd) = battery.(elde).(sd).updateFlux(state.(elde).(sd));
                    state.(elde).(sd) = battery.(elde).(sd).updateAccumTerm(state.(elde).(sd), state0.(elde).(sd), dt);
                    state.(elde).(sd) = battery.(elde).(sd).updateMassConservation(state.(elde).(sd));
                end
            end
            
            %% setup relation between E and I at positive current collectror
            
            state = model.setupEIEquation(state);
            
            %% Set up the governing equations
            
            eqs = {};
            
            %% We collect mass and charge conservation equations for the electrolyte and the electrodes
            massConsScaling = model.con.F;
            
            eqs{end + 1} = state.(elyte).massCons*massConsScaling;
            eqs{end + 1} = state.(elyte).chargeCons;
            eqs{end + 1} = state.(ne).chargeCons;
            eqs{end + 1} = state.(pe).chargeCons;

            names = {'elyte_massCons'    , ...
                     'elyte_chargeCons'  , ...
                     'ne_chargeCons'     , ...
                     'pe_chargeCons'};
            
            if model.(ne).useSimplifiedDiffusionModel
                eqs{end + 1} = state.(ne).massCons*massConsScaling;
                eqs{end + 1} = state.(ne).(sd).solidDiffusionEq*massConsScaling.*battery.(ne).(itf).G.cells.volumes/dt;
                names = horzcat(names, {'ne_masscons', 'ne_sd_soliddiffeq'});
            else
                eqs{end + 1} = 1e18*state.(ne).(sd).massCons;
                names{end + 1} = 'ne_sd_soliddiffeq';

            end
            
            if model.(pe).useSimplifiedDiffusionModel
                eqs{end + 1} = state.(pe).massCons*massConsScaling;
                eqs{end + 1} = state.(pe).(sd).solidDiffusionEq*massConsScaling.*battery.(pe).(itf).G.cells.volumes/dt;
                names = horzcat(names, {'pe_masscons', 'pe_sd_soliddiffeq'});
            else
                eqs{end + 1} = 1e18*state.(pe).(sd).massCons;
                names{end + 1} = 'pe_sd_soliddiffeq';
            end

            
            eqs{end + 1} = state.EIeq;
            % we add the control equation
            I = state.(pe).I;
            E = state.(pe).E;
            [val, ctrltype] = drivingForces.src(time, value(I), value(E));
            switch ctrltype
              case 'I'
                eqs{end + 1} = I - val;
              case 'E'
                eqs{end + 1} = (E - val)*1e5;
            end
            names = horzcat(names, {'EIeq' , 'controlEq'});
            
            types = repmat({'cells'}, 1, numel(names));

            primaryVars = model.getPrimaryVariables();

            %% setup LinearizedProblem that can be processed by MRST Newton API
            problem = LinearizedProblem(eqs, types, names, primaryVars, state, dt);
            
        end

        function state = updateTemperature(model, state)
        % Dispatch the temperature in all the submodels

            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            cc    = 'CurrentCollector';
            
            % (here we assume that the ThermalModel has the "parent" grid)
            state.(elyte).T = state.T(model.(elyte).G.mappings.cellmap);
            state.(ne).T = state.T(model.(ne).G.mappings.cellmap);
            state.(pe).T = state.T(model.(pe).G.mappings.cellmap);
            
            % Update temperature in the active materials of the electrodes.
            state.(ne) = model.(ne).dispatchTemperature(state.(ne));
            state.(pe) = model.(pe).dispatchTemperature(state.(pe));
            
        end
        
        
        function state = updateElectrolyteCoupling(model, state)
        % Assemble the electrolyte coupling by adding the ion sources from the electrodes
            
            battery = model;
            elyte   = 'Electrolyte';
            ne      = 'NegativeElectrode';
            pe      = 'PositiveElectrode';
            itf     = 'Interface';
            
            vols = battery.(elyte).G.cells.volumes;
            F = battery.con.F;
            
            couplingterms = battery.couplingTerms;

            elyte_c_source = zeros(battery.(elyte).G.cells.num, 1);
            elyte_e_source = zeros(battery.(elyte).G.cells.num, 1);
            
            % setup AD 
            phi = state.(elyte).phi;
            if isa(phi, 'ADI')
                adsample = getSampleAD(phi);
                adbackend = model.AutoDiffBackend;
                elyte_c_source = adbackend.convertToAD(elyte_c_source, adsample);
            end
            
            coupnames = model.couplingNames;
            
            ne_R = state.(ne).(itf).R;
            coupterm = getCoupTerm(couplingterms, 'NegativeElectrode-Electrolyte', coupnames);
            elytecells = coupterm.couplingcells(:, 2);
            elyte_c_source(elytecells) = ne_R.*vols(elytecells);
            
            pe_R = state.(pe).(itf).R;
            coupterm = getCoupTerm(couplingterms, 'PositiveElectrode-Electrolyte', coupnames);
            elytecells = coupterm.couplingcells(:, 2);
            elyte_c_source(elytecells) = pe_R.*vols(elytecells);
            
            elyte_e_source = elyte_c_source.*battery.(elyte).sp.z(1)*F; 
            
            state.Electrolyte.massSource = elyte_c_source; 
            state.Electrolyte.eSource = elyte_e_source;
            
        end
        
        function state = updateAccumTerms(model, state, state0, dt)
        % Assemble the accumulation terms for transport equations (in electrolyte and electrodes)
            
            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            
            cdotcc  = (state.(elyte).c - state0.(elyte).c)/dt;
            effectiveVolumes = model.(elyte).volumeFraction.*model.(elyte).G.cells.volumes;
            massAccum  = effectiveVolumes.*cdotcc;
            state.(elyte).massAccum = massAccum;
            
        end
        
        function state = updateElectrodeCoupling(model, state)
        % Setup the electrode coupling by updating the potential and concentration of the electrolyte in the active
        % component of the electrodes. There, those quantities are considered as input and used to compute the reaction
        % rate.
        %
        % WARNING : at the moment, we do not pass the concentrations
            
            bat = model;
            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            itf    = 'Interface';
            
            eldes = {ne, pe};
            phi_elyte = state.(elyte).phi;
            c_elyte = state.(elyte).cs{1};
            
            elyte_cells = zeros(model.G.cells.num, 1);
            elyte_cells(bat.(elyte).G.mappings.cellmap) = (1 : bat.(elyte).G.cells.num)';

            for ind = 1 : numel(eldes)
                elde = eldes{ind};
                state.(elde).(itf).phiElectrolyte = phi_elyte(elyte_cells(bat.(elde).G.mappings.cellmap));
                state.(elde).(itf).cElectrolyte = c_elyte(elyte_cells(bat.(elde).G.mappings.cellmap));
            end
            
        end

        function state = setupExternalCouplingNegativeElectrode(model, state)
        %
        % Setup external electronic coupling of the negative electrode
        %
         
            battery = model;
            ne = 'NegativeElectrode';

            phi = state.(ne).phi;
            
            couplingterms = battery.couplingTerms;
            coupnames = battery.couplingNames;
            coupterm = getCoupTerm(couplingterms, 'Exterior-NegativeElectrode', coupnames);
            
            jBcSource = phi*0.0; %NB hack to initialize zero ad
            sigmaeff = model.(ne).EffectiveElectricalConductivity;
            faces = coupterm.couplingfaces;
            % We impose potential equal to zero at negative electrode
            bcval = 0;
            [t, cells] = model.(ne).operators.harmFaceBC(sigmaeff, faces);
            jBcSource(cells) = jBcSource(cells) + t.*(bcval - phi(cells));
            
            state.(ne).jBcSource = jBcSource;
            
        end
        
        function state = setupExternalCouplingPositiveElectrode(model, state)
        %
        % Setup external electronic coupling of the positive electrode at the current collector
        %            
         
            battery = model;
            pe = 'PositiveElectrode';
            
            phi = state.(pe).phi;
            E = state.(pe).E;
            
            couplingterms = battery.couplingTerms;
            coupnames = battery.couplingNames;
            coupterm = getCoupTerm(couplingterms, 'Exterior-PositiveElectrode', coupnames);
            
            jBcSource = phi*0.0; %NB hack to initialize zero ad
            sigmaeff = model.(pe).EffectiveElectricalConductivity;
            faces = coupterm.couplingfaces;
            % We impose potential equal to value given by E at the positive electrode
            bcval = E;
            [t, cells] = model.(pe).operators.harmFaceBC(sigmaeff, faces);
            jBcSource(cells) = jBcSource(cells) + t.*(bcval - phi(cells));
            
            state.(pe).jBcSource = jBcSource;
        
        end

        function state = setupEIEquation(model, state)
            
            battery = model;
            pe = 'PositiveElectrode';
            
            couplingterms = battery.couplingTerms;
            coupnames = battery.couplingNames;
            coupterm = getCoupTerm(couplingterms, 'Exterior-PositiveElectrode', coupnames);
            
            I = state.(pe).I;
            E = state.(pe).E;
            phi = state.(pe).phi;
            
            faces = coupterm.couplingfaces;
            cond_pcc = model.(pe).EffectiveElectricalConductivity;
            [trans_pcc, cells] = model.(pe).operators.harmFaceBC(cond_pcc, faces);
            state.EIeq = sum(trans_pcc.*(state.(pe).phi(cells) - E)) - I;

        end
        
        
        function state = initStateAD(model, state)
            
            [pnames, extras]  = model.getPrimaryVariables();
            
            vars = cell(numel(pnames),1);
            for i=1:numel(pnames)
                vars{i} = model.getProp(state,pnames{i});
            end
            % Get the AD state for this model           
            [vars{:}] = model.AutoDiffBackend.initVariablesAD(vars{:});
            newstate =struct();
        
            for i = 1 : numel(pnames)
               newstate = model.setNewProp(newstate, pnames{i}, vars{i});
            end
            
            for i = 1 : numel(extras)
                var = model.getProp(state, extras{i});
                assert(isnumeric(var));
                newstate = model.setNewProp(newstate, extras{i}, var);
            end
            
            time = state.time;
            state = newstate;
            state.time = time;
            
        end 
        
        function [p, extra] = getPrimaryVariables(model)
            
            bat = model;
            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            sd    = 'SolidDiffusion';
            
            p = {{elyte, 'c'}      , ...
                 {elyte, 'phi'}    , ...   
                 {ne, 'phi'}       , ...   
                 {pe, 'phi'}       , ...   
                 {pe, 'E'}         , ...
                 {pe, 'I'}};
            
            if model.(ne).useSimplifiedDiffusionModel
                p{end + 1} = {ne, 'c'};
                p{end + 1} = {ne, sd, 'cSurface'};
            else
                p{end + 1} = {ne, sd, 'c'};
            end
            
            if model.(pe).useSimplifiedDiffusionModel
                p{end + 1} = {pe, 'c'};
                p{end + 1} = {pe, sd, 'cSurface'};
            else
                p{end + 1} = {pe, sd, 'c'};
            end
            
            extra = [];
            
        end
        
        
        function validforces = getValidDrivingForces(model)
        
            validforces=struct('src', [], 'stopFunction', []); 
            
        end
        
        function model = validateModel(model, varargin)

            model.Electrolyte.AutoDiffBackend = model.AutoDiffBackend;
            model.Electrolyte = model.Electrolyte.validateModel(varargin{:});
            
            model.PositiveElectrode.AutoDiffBackend = model.AutoDiffBackend;
            model.PositiveElectrode                 = model.PositiveElectrode.validateModel(varargin{:});
            model.NegativeElectrode.AutoDiffBackend = model.AutoDiffBackend;
            model.NegativeElectrode                 = model.NegativeElectrode.validateModel(varargin{:});
        
        end
        

        function [state, report] = updateState(model, state, problem, dx, drivingForces)

            [state, report] = updateState@BaseModel(model, state, problem, dx, drivingForces);
            
            %% cap concentrations
            elyte = 'Electrolyte';
            ne    = 'NegativeElectrode';
            pe    = 'PositiveElectrode';
            itf   = 'Interface';
            sd    = 'SolidDiffusion';
            
            cmin = model.cmin;
            
            state.(elyte).c = max(cmin, state.(elyte).c);
            
            eldes = {ne, pe};
            for ind = 1 : numel(eldes)
                elde = eldes{ind};
                cmax = model.(elde).(itf).cmax;
                if model.(elde).useSimplifiedDiffusionModel
                    state.(elde).c = max(cmin, state.(elde).c);
                    state.(elde).c = min(cmax, state.(elde).c);
                else
                    state.(elde).(sd).c = max(cmin, state.(elde).(sd).c);
                    state.(elde).(sd).c = min(cmax, state.(elde).(sd).c);
                end
            end
            
            report = [];
            
        
        end
        
        function outputvars = extractGlobalVariables(model, states)

            pe = 'PositiveElectrode';

            ns = numel(states);
            ws = cell(ns, 1);
            
            for i = 1 : ns
                E    = states{i}.(pe).E;
                I    = states{i}.(pe).I;
                time = states{i}.time;
                
                outputvars{i} = struct('E'   , E   , ...
                                       'I'   , I   , ...
                                       'time', time);
            end
        end
        
        function [state, report] = updateAfterConvergence(model, state0, state, dt, drivingForces)

            report = [];
            
        end
        
    end
    
end



%{
Copyright 2009-2021 SINTEF Industry, Sustainable Energy Technology
and SINTEF Digital, Mathematics & Cybernetics.

This file is part of The Battery Modeling Toolbox BatMo

BatMo is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

BatMo is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with BatMo.  If not, see <http://www.gnu.org/licenses/>.
%}
