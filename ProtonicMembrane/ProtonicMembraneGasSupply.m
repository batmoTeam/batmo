classdef ProtonicMembraneGasSupply < BaseModel
    
    properties

        GasSupplyBc
        Control
        
        constants
        
        molecularWeights
        permeability
        viscosity
        diffusionCoefficients % vector of diffusion coefficients, one per component
        T % Temperature
        control % Control structure
        
        nGas   % Number of gas (each of them will have a partial pressure). Only needed when gasSupplyType == 'coupled'
        gasInd % Structure whose fieldname give index number of the corresponding gas component.

        couplingTerms

        helpers
        % - bcToCoupMap        : map from the bc values vector to the control vector (bc values corresponding to same control are summed up)
        % - coupToBcMap        : map from the control vector to the bc values vector  (each control value are dispached over the bc values where it apply)
        % - pressureMap        : map pressure values in state.Control.rate to those ones (only) that are given by a pressure control
        %                        (see use in method updateControlSetup)
        % - pressureValues     : pressure values given by the control 
        % - rateMap            : map rate values in state.Control.rate to thoes ones (only) that are  given by a rate control (see use in method updateControlSetup)
        % - rateValues         : rate values given by the control 
        % - massfractionMap    : See method updateBcMassFraction. pick-up the massfraction values from GasSupplyBc bc that are imposed by some control 
        % - massfractionValues : See method updateBcMassFraction. use to assign the massfraction values
        % - bccells            : 
        % - bcfaces            : 
        % - bccellfacecouptbl  : 
        
    end
    
    methods
        
        function model = ProtonicMembraneGasSupply(inputparams)
            
            model = model@BaseModel();

            fdnames = {'G'                    , ...
                       'molecularWeights'     , ...
                       'permeability'         , ...
                       'viscosity'            , ...
                       'diffusionCoefficients', ...
                       'control'              , ...
                       'couplingTerms'        , ...
                       'T'};
            
            model = dispatchParams(model, inputparams, fdnames);

            model.GasSupplyBc = ProtonicMembraneGasSupplyBc(inputparams);
            model.Control     = BaseModel();
            
            model.constants = PhysicalConstants();
            
            model.gasInd.H2O = 1;
            model.gasInd.O2  = 2;
            model.nGas = 2;

            model = model.setupControl();

        end

        function model = setupForSimulation(model)
            
            model.isRootSimulationModel = true;

            shortNames = {'1'                , 'H2O'      ;
                          '2'                , 'O2'       ;
                          'massConses'       , 'massCons' ;
                          'GasSupplyBc'      , 'bc'       ;
                          'controlEquations' , 'ctrleqs'  ;
                          'bcFluxEquations'  , 'bceqs'} ;
            
            model = model.equipModelForComputation('shortNames', shortNames);
            
        end
        
        function model = registerVarAndPropfuncNames(model)
            
            model = registerVarAndPropfuncNames@BaseModel(model);
            
            nGas = model.nGas;
            nCoup = numel(model.couplingTerms);
            
            varnames = {};

            % Components volume fractions
            varnames{end + 1} = VarName({}, 'massfractions', nGas);
            % Total pressure
            varnames{end + 1} = 'pressure';
            % Gas densities 
            varnames{end + 1} = 'density';
            % Gas densities 
            varnames{end + 1} = VarName({}, 'densities', nGas);
            % Mass accumulation terms
            varnames{end + 1} = VarName({}, 'massAccums', nGas);
            % Mass Flux terms
            varnames{end + 1} = VarName({}, 'massFluxes', nGas);
            % Mass Source terms
            varnames{end + 1} = VarName({}, 'massSources', nGas);
            % Mass Conservation equations
            varnames{end + 1} = VarName({}, 'massConses', nGas);
            %% Control values
            % Rate (total mass) at the control
            % NOTE : Rate > 0 when injecting (opposity convention as massFlux)
            varnames{end + 1} = {'Control', 'rate'};
            % total pressure at the control
            varnames{end + 1} = {'Control', 'pressure'};
            % Pressure equation for the control pressure
            varnames{end + 1} = {'Control', 'pressureEq'};
            % Rate equation for the control equation
            varnames{end + 1} = {'Control', 'rateEq'};
            % control equation 
            varnames{end + 1} = {'Control', 'setupEq'};
            
            model = model.registerVarNames(varnames);

            fn = @ProtonicMembraneGasSupply.updateMassFraction;
            inputvarnames = {VarName({}, 'massfractions', nGas, 1)};
            outputvarname = VarName({}, 'massfractions', nGas, 2);
            model = model.registerPropFunction({outputvarname, fn, inputvarnames});

            fn = @(model, state) ProtonicMembraneGasSupply.updateDensity(model, state);
            fn = {fn, @(prop) PropFunction.literalFunctionCallSetupFn(prop)};
            inputvarnames = {VarName({}, 'massfractions', nGas), 'pressure'};
            model = model.registerPropFunction({'density', fn, inputvarnames});

            fn = @ProtonicMembraneGasSupply.updateBCequations;
            inputvarnames = {VarName({'GasSupplyBc'}, 'massFluxes', nGas)   , ...
                             VarName({'GasSupplyBc'}, 'massfractions', nGas), ...
                             VarName({'GasSupplyBc'}, 'densities', nGas)    , ...
                             VarName({'GasSupplyBc'}, 'pressure')           , ...
                             VarName({'GasSupplyBc'}, 'density')            , ...
                             VarName({}, 'massfractions', nGas)             , ...
                             VarName({}, 'densities', nGas)                 , ...
                             VarName({}, 'pressure')                        , ...
                             VarName({}, 'density')                         , ...
                             };
            outputvarname = VarName({'GasSupplyBc'}, 'bcFluxEquations', nGas);
            model = model.registerPropFunction({outputvarname, fn, inputvarnames});

            fn = @ProtonicMembraneGasSupply.updateControlPressureEquation;
            inputvarnames = {{'GasSupplyBc', 'pressure'}, {'Control', 'pressure'}};
            model = model.registerPropFunction({{'Control', 'pressureEq'}, fn, inputvarnames});

            fn = @ProtonicMembraneGasSupply.updateControlSetup;
            inputvarnames = {{'Control', 'pressure'}, ...
                             {'Control', 'rate'}};
            model = model.registerPropFunction({{'Control', 'setupEq'}, fn, inputvarnames});

            fn = @ProtonicMembraneGasSupply.updateBcMassFraction;
            inputvarnames = {VarName({}, 'massfractions', nGas, 1)};
            outputvarname = VarName({'GasSupplyBc'}, 'massfractions', nGas, 1);
            model = model.registerPropFunction({outputvarname, fn, inputvarnames});
            
            for igas = 1 : nGas

                fn = @ProtonicMembraneGasSupply.updateRateEq;
                inputvarnames = {VarName({'GasSupplyBc'}, 'massFluxes', nGas, igas), ...
                                 VarName({'Control'}, 'rate')};
                model = model.registerPropFunction({{'Control', 'rateEq'}, fn, inputvarnames});

                fn = @(model, state) ProtonicMembraneGasSupply.updateDensities(model, state);
                fn = {fn, @(prop) PropFunction.literalFunctionCallSetupFn(prop)};
                inputvarnames = {'density', ...
                                 VarName({}, 'massfractions', nGas, igas)};
                outputvarname = VarName({}, 'densities', nGas, igas);
                model = model.registerPropFunction({outputvarname, fn, inputvarnames});

                fn = @ProtonicMembraneGasSupply.updateMassFluxes;
                inputvarnames = {VarName({}, 'massfractions', nGas, igas), ...
                                 VarName({}, 'densities', nGas, igas), ...
                                 'density', 'pressure'};
                outputvarname = VarName({}, 'massFluxes', nGas, igas);
                model = model.registerPropFunction({outputvarname, fn, inputvarnames});
                
                fn = @ProtonicMembraneGasSupply.updateMassAccums;
                fn = {fn, @(prop) PropFunction.accumFuncCallSetupFn(prop)};
                inputvarnames = {VarName({}, 'densities', nGas, igas)};
                outputvarname = VarName({}, 'massAccums', nGas, igas);
                model = model.registerPropFunction({outputvarname, fn, inputvarnames});
                                
                fn = @ProtonicMembraneGasSupply.updateMassConses;
                inputvarnames = {VarName({}, 'massAccums', nGas, igas), ...
                                 VarName({}, 'massFluxes', nGas, igas), ...
                                 VarName({}, 'massSources', nGas, igas)};
                outputvarname = VarName({}, 'massConses', nGas, igas);
                model = model.registerPropFunction({outputvarname, fn, inputvarnames});

                fn = @ProtonicMembraneGasSupply.updateMassSources;
                inputvarnames = {VarName({'GasSupplyBc'}, 'massFluxes', nGas, igas)};
                outputvarname = VarName({}, 'massSources', nGas, igas);
                model = model.registerPropFunction({outputvarname, fn, inputvarnames});
                
            end
            
        end


        function model = setupControl(model)

            % Two crontol type indexed 'pressure-composition' : 1, 'flux-composition' : 2
            typetbl.type = [1; 2];
            typetbl = IndexArray(typetbl);

            % Two values are given for each control. They are indexed by comp
            % 'pressure-composition' : 1) pressure 2) H2O volume fraction
            % 'flux-composition' : 1) rate 2) H2O volume fraction
            %
            comptbl.comp = [1; 2];
            comptbl = IndexArray(comptbl);

            couplingTerms = model.couplingTerms;
            ctrl = model.control;

            ctrlvals = [];
            % The control values ctrlvals are stored in comptypecouptbl
            comptypecouptbl = IndexArray([], 'fdnames', {'comp', 'type', 'coup'});

            function icoupterm = findCouplingTerm(ictrl)
                name = ctrl(ictrl).name;
                icoupterm = [];
                for icoup = 1 : numel(couplingTerms)
                    if strcmp(name, couplingTerms{icoup}.name)
                        icoupterm = icoup;
                        return
                    end
                end
                error('couplingTerm structure not found');
            end
            
            for ictrl = 1 : numel(ctrl)

                ctrlinput = ctrl(ictrl);
                
                clear typetbl2
                switch ctrlinput.type
                  case 'pressure-composition'
                    typetbl2.type = 1;
                  case 'rate-composition'
                    typetbl2.type = 2;
                  otherwise
                    error('ctrlinput type not recognized');
                end
                typetbl2 = IndexArray(typetbl2);
                comptypecouptbl2 = crossIndexArray(comptbl, typetbl2, {});

                icoupterm = findCouplingTerm(ictrl);
                
                comptypecouptbl2 =  comptypecouptbl2.addInd('coup', icoupterm);
                vals2 = ctrlinput.values;

                comptypecouptbl = concatIndexArray(comptypecouptbl, comptypecouptbl2, {});
                ctrlvals = [ctrlvals; vals2];
                
            end

            couptbl.coup = (1 : numel(couplingTerms))';
            couptbl = IndexArray(couptbl);
            
            bccellfacecouptbl = IndexArray([], 'fdnames', {'faces', 'cells', 'coup'});

            for icoup = 1 : numel(couplingTerms)

                clear bccellfacecouptbl2;
                bccellfacecouptbl2.faces = couplingTerms{icoup}.couplingfaces;
                bccellfacecouptbl2.cells = couplingTerms{icoup}.couplingcells;
                bccellfacecouptbl2 = IndexArray(bccellfacecouptbl2);
                nc = bccellfacecouptbl2.num;
                bccellfacecouptbl2 =  bccellfacecouptbl2.addInd('coup', icoup*ones(nc, 1));

                bccellfacecouptbl = concatIndexArray(bccellfacecouptbl, bccellfacecouptbl2, {});

            end

            map          = TensorMap;
            map.fromTbl  = bccellfacecouptbl;
            map.toTbl    = couptbl;
            map.mergefds = {'coup'};

            M = SparseTensor;
            M = M.setFromTensorMap(map);
            M = M.getMatrix();

            helpers.bcToCoupMap = M;
            helpers.coupToBcMap = M';
            
            bccellfacecomptypecouptbl = crossIndexArray(bccellfacecouptbl, comptypecouptbl, {'coup'});

            %%  setup pressureMap
            
            clear comptypetbl2
            comptypetbl2.type = 1; % pressure index is 1
            comptypetbl2.comp = 1; % first index gives pressure value
            comptypetbl2 = IndexArray(comptypetbl2);
            comptypecouptbl2  = crossIndexArray(comptypetbl2, comptypecouptbl, {'type', 'comp'});
            
            map          = TensorMap();
            map.fromTbl  = couptbl;
            map.toTbl    = comptypecouptbl2;
            map.mergefds = {'coup'};

            M = SparseTensor();
            M = M.setFromTensorMap(map);
            M = M.getMatrix();

            helpers.pressureMap = M;

            map          = TensorMap();
            map.fromTbl  = comptypecouptbl;
            map.toTbl    = comptypecouptbl2;
            map.mergefds = {'coup', 'comp', 'type'};
            map          = map.setup();

            helpers.pressureValues = map.eval(ctrlvals);

            %%  setup rateMap
            
            clear comptypetbl2
            comptypetbl2.type = 2; % rate index is 2
            comptypetbl2.comp = 1; % first index gives rate value
            comptypetbl2 = IndexArray(comptypetbl2);
            comptypecouptbl2 = crossIndexArray(comptypetbl2, comptypecouptbl, {'type', 'comp'});
            
            map          = TensorMap();
            map.fromTbl  = couptbl;
            map.toTbl    = comptypecouptbl2;
            map.mergefds = {'coup'};

            M = SparseTensor();
            M = M.setFromTensorMap(map);
            M = M.getMatrix();

            helpers.rateMap = M;

            map          = TensorMap();
            map.fromTbl  = comptypecouptbl;
            map.toTbl    = comptypecouptbl2;
            map.mergefds = {'coup', 'comp', 'type'};
            map          = map.setup();

            helpers.rateValues = map.eval(ctrlvals);


            %%  setup massfractionMap and massfractionValues
            
            clear comptbl2
            comptbl2.comp = 2; % second index gives mass fraction, for both type
            comptbl2 = IndexArray(comptbl2);
            comptypecouptbl2 = crossIndexArray(comptbl2, comptypecouptbl, {'comp'});
            comptypecouptbl2 = sortIndexArray(comptypecouptbl2, {'coup', 'comp', 'type'});

            assert(comptypecouptbl2.num == couptbl.num, 'we expect one value per coupling');
            
            map = TensorMap();
            map.fromTbl = comptypecouptbl;
            map.toTbl = comptypecouptbl2;
            map.mergefds = {'coup', 'comp', 'type'};
            map = map.setup();

            mfvalues= map.eval(ctrlvals);
            
            bcMassfractions{1} = (helpers.coupToBcMap)*mfvalues;
            bcMassfractions{2} = 1 - bcMassfractions{1};

            helpers.bcMassfractions = bcMassfractions;
            
            helpers.bccells           = bccellfacecouptbl.get('cells');
            helpers.bcfaces           = bccellfacecouptbl.get('faces');
            helpers.bccellfacecouptbl = bccellfacecouptbl;
            
            model.helpers = helpers;
            
        end
        function state = updateControlSetup(model, state)

            helpers = model.helpers;

            eqs = {};

            map = helpers.rateMap;
            val = helpers.rateValues;

            if ~isempty(val)
                eqs{end + 1} = 1./val.*(map*state.Control.rate) - 1; % equations are scaled to one
            end
            
            map = helpers.pressureMap;
            val = helpers.pressureValues;
            
            if ~isempty(val)
                eqs{end + 1} = 1./val.*(map*state.Control.pressure) - 1; % equations are scaled to one
            end

            state.Control.setupEq = vertcat(eqs{:});

        end

        function state = updateBcMassFraction(model, state)

            state.GasSupplyBc.massfractions{1} = model.helpers.bcMassfractions{1};
            
        end
        
        function state = updateMassSources(model, state)

            nGas = model.nGas;
            bccells = model.helpers.bccells;
            
            for igas = 1 : nGas
                src = 0.*state.pressure; % hacky initialization to get AD
                src(bccells) = state.GasSupplyBc.massFluxes{igas};
                srcs{igas} = - src;
            end

            state.massSources = srcs;
            
        end
        

        function state = updateMassFraction(model, state)

            state.massfractions{2} = 1 - state.massfractions{1};
            
        end

        
        function state = updateControlPressureEquation(model, state)

            map = model.helpers.coupToBcMap;
            
            pcontrol = state.Control.pressure;
            pbc      = state.GasSupplyBc.pressure;

            state.Control.pressureEq = pbc - map*pcontrol;
            
        end


        function state = updateRateEq(model, state)

            map = model.helpers.bcToCoupMap;
            nGas = model.nGas;

            eq = state.Control.rate;
            
            for igas = 1 : nGas
                % Note sign due to convention
                eq = eq +  map*state.GasSupplyBc.massFluxes{igas};

            end

            state.Control.rateEq = eq;
            
        end

        function state = updateBCequations(model, state)

            nGas = model.nGas;
            K    = model.permeability;
            mu   = model.viscosity;
            D    = model.diffusionCoefficients;
            
            bccells = model.helpers.bccells;
            bcfaces = model.helpers.bcfaces;

            Tbc = model.G.getBcTrans(bcfaces);

            pIn   = state.pressure(bccells);
            pBc   = state.GasSupplyBc.pressure;
            rhoBc = state.GasSupplyBc.density ;
            mfsBc = state.GasSupplyBc.massfractions;

            % Compute upwind direction
            inward = find((value(pBc - pIn)) >= 0);
            
            for igas = 1 : nGas

                mfBc   = mfsBc{igas};
                
                bcFlux    = state.GasSupplyBc.massFluxes{igas};
                rhoInigas = state.densities{igas}(bccells);
                rhoBcigas = state.GasSupplyBc.densities{igas};

                mfBcUpwind = state.massfractions{igas}(bccells);
                mfBcUpwind(inward)= mfBc(inward);
                
                bceqs{igas} = rhoBc.*mfBcUpwind*K/mu.*Tbc.*(pIn - pBc) + D(igas).*Tbc.*(rhoInigas - rhoBcigas) - bcFlux;

            end

            state.GasSupplyBc.bcFluxEquations = bceqs;
            
        end
        

        function state = updateMassFluxes(model, state)

            K    = model.permeability;
            mu   = model.viscosity;
            nGas = model.nGas;
            D    = model.diffusionCoefficients;
            
            p   = state.pressure;
            mfs = state.massfractions;
            rho = state.density;

            v = assembleFlux(model, p, rho.*K/mu);
            
            for igas = 1 : nGas

                rhoigas = state.densities{igas};
                state.massFluxes{igas} = assembleUpwindFlux(model, v, mfs{igas}) + assembleHomogeneousFlux(model, rhoigas, D(igas));
                
            end
            
        end
        
        function state = updateMassAccums(model, state, state0, dt)

            vols = model.G.getVolumes();
            nGas = model.nGas;

            for igas = 1 : nGas
                
                rhoigas  = state.densities{igas};
                rho0igas = state0.densities{igas};

                state.massAccums{igas} = vols.*(rhoigas - rho0igas)/dt;
                
            end
            
        end

        
        function state = updateMassConses(model, state)

            nGas = model.nGas;

            for igas = 1 : nGas

                state.massConses{igas} = state.massAccums{igas} + model.G.getDiv(state.massFluxes{igas}) - state.massSources{igas};
                
            end
            
        end
        
        function initstate = setupInitialState(model)

            nGas    = model.nGas;
            nc      = model.G.getNumberOfCells();
            nbc     = numel(model.helpers.bcfaces);
            gasInd  = model.gasInd;
            control = model.control;


            names = arrayfun(@(ctrl) ctrl.name, control, 'uniformoutput', false);
            [lia, locb] = ismember('External output', names);
            assert(lia, 'External output control not found');
            control = control(locb);

            assert(strcmp(control.type, 'pressure-composition'), 'Here we expect pressure controled output');
            
            values = control.values;

            p  = values(1);
            mf = values(2);
            
            initstate.pressure         = p*ones(nc, 1);
            initstate.massfractions{1} = mf *ones(nc, 1);
            initstate.massfractions{2} = (1 - mf) *ones(nc, 1);
            
            initstate.GasSupplyBc.pressure               = p*ones(nbc, 1);
            initstate.GasSupplyBc.massFluxes{gasInd.H2O} = zeros(nbc, 1);
            initstate.GasSupplyBc.massFluxes{gasInd.O2}  = zeros(nbc, 1);
            initstate.GasSupplyBc.massfractions{1}       = mf*ones(nbc, 1);
            
            nctrl = numel(model.control);
            initstate.Control.rate             = zeros(nctrl, 1);
            initstate.Control.pressure         = p*ones(nctrl, 1);
            
            initstate = model.evalVarName(initstate, VarName({}, 'massfractions', nGas, 2));
            initstate = model.evalVarName(initstate, VarName({}, 'density'));
            initstate = model.evalVarName(initstate, 'densities');
            
        end

        function newstate = addVariablesAfterConvergence(model, newstate, state)

            newstate = addVariablesAfterConvergence@BaseModel(model, newstate, state);

            newstate.massfractions{2} = state.massfractions{2};
            newstate.density          = state.density;

            nGas = model.nGas;
            
            for igas = 1 : nGas
                newstate.densities{igas} = state.densities{igas};
            end
            
        end
        
        function forces = getValidDrivingForces(model)

            forces = getValidDrivingForces@PhysicalModel(model);
            forces.src = [];
            
        end

        function model = validateModel(model, varargin)
        % do nothing
        end

        function [state, report] = updateState(model, state, problem, dx, drivingForces)

            [state, report] = updateState@BaseModel(model, state, problem, dx, drivingForces);

            varnames = {{'GasSupplyBc', 'pressure'}, ...
                        {'pressure'}};

            for ivar = 1 : numel(varnames)

                varname = varnames{ivar};
                state = model.capProperty(state, varname, 0);

            end

            state = model.capProperty(state, {'massfractions', 1}, 0, 1);
            
        end

        
    end

    methods(Static)
        
        function state = updateDensities(model, state)

            nGas = model.nGas;
            
            for igas = 1 : nGas
                state.densities{igas} = state.density.*state.massfractions{igas};
            end
            
        end

        
        function state = updateDensity(model, state)

            Mws  = model.molecularWeights;
            T    = model.T;
            nGas = model.nGas;
            c    = model.constants;

            p   = state.pressure;
            mfs = state.massfractions;

            coef = 0*p;
            
            for igas = 1 : nGas

                coef = coef + mfs{igas}/Mws(igas);
                
            end

            state.density = p./(c.R*T*coef);
            
        end

    end
    
end
