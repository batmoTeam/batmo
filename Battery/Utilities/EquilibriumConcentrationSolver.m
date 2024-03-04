classdef EquilibriumConcentrationSolver < BaseModel

    properties

        % Each electrode has the following fields
        % - numberOfActiveMaterial   : number of active materials (nam)
        % - volumes                  : vector (dimension nam) with volume of each active material
        % - saturationConcentrations : vector (dimension nam) with saturation concentrations for each active material
        % - thetaMaxs                : vector (dimension nam) with maximum concentation for each active material
        % - thetaMins                : vector (dimension nam) with minimum concentation for each active material
        % - computeOCPs              : cell array where each cell is a function computing the OCP from a given concentration.
        
        NegativeElectrode
        PositiveElectrode

        voltage
        totalAmount % in mol

        % Temperature (may be needed in OCP computations)
        T
        
    end


    methods

        function model = EquilibriumConcentrationSolver(batterymodel)

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            model.subModelNameList = {ne, pe};

            model = model.setupFromBatteryModel(batterymodel);
            model = model.equipModelForComputation();
            
        end

        function model = setupFromBatteryModel(model, batterymodel)
                
            model.T = batterymodel.initT;
            
            ne  = 'NegativeElectrode';
            pe  = 'PositiveElectrode';
            co  = 'Coating';
            itf = 'Interface';
            
            eldes = {ne, pe};

            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};

                switch elde
                  case ne
                    gsmax = 'guestStoichiometry100';
                    gsmin = 'guestStoichiometry0';
                  case pe
                    gsmax = 'guestStoichiometry0';
                    gsmin = 'guestStoichiometry100';
                  otherwise
                    error('Electrode not recognised');
                end
                  
                % For the moment we support only 2 active materials
                if ~isempty(batterymodel.(elde).(co).ActiveMaterial1)
                    
                    comodel = batterymodel.(elde).(co);
                    nam = 2;

                    satConcs    = nan(nam, 1);
                    thetaMaxs   = nan(nam, 1);
                    thetaMins   = nan(nam, 1);
                    vfs         = nan(nam, 1);
                    vs          = nan(nam, 1);
                    computeOCPs = cell(nam, 1);
                    
                    for iam = 1 : nam

                        switch iam
                          case 1
                            am = 'ActiveMaterial1';
                          case 2
                            am = 'ActiveMaterial2';
                          otherwise
                            error('iam index not accepted');
                        end
                        
                        indam = comodel.compInds.(am);

                        satConcs(iam)    = comodel.(am).(itf).saturationConcentration;
                        thetaMaxs(iam)   = comodel.(am).(itf).(gsmax);
                        thetaMins(iam)   = comodel.(am).(itf).(gsmin);
                        vfs(iam)         = comodel.volumeFractions(indam)*comodel.volumeFraction;
                        vs(iam)          = sum(comodel.G.getVolumes()*vfs(iam));
                        computeOCPs{iam} = @(c) comodel.(am).(itf).computeOCPFunc(c, model.T, satConcs(iam));

                    end

                    model.(elde).numberOfActiveMaterial   = nam;
                    model.(elde).saturationConcentrations = satConcs;
                    model.(elde).thetaMaxs                = thetaMaxs;
                    model.(elde).thetaMins                = thetaMins;
                    model.(elde).volumes                  = vs;
                    model.(elde).computeOCPs              = computeOCPs;
                    
                else

                    comodel = batterymodel.(elde).(co);
                    
                    am = 'ActiveMaterial';

                    indam = comodel.compInds.(am);

                    satConcs  = comodel.(am).(itf).saturationConcentration;
                    thetaMaxs = comodel.(am).(itf).(gsmax);
                    thetaMins = comodel.(am).(itf).(gsmin);
                    vfs       = comodel.volumeFractions(indam)*comodel.volumeFraction;
                    vs        = sum(comodel.G.getVolumes()*vfs);

                    computeOCPs = cell(1, 1);
                    computeOCPs{1} = @(c) comodel.(am).(itf).computeOCPFunc(c, model.T, satConcs);

                    model.(elde).numberOfActiveMaterial   = 1;
                    model.(elde).saturationConcentrations = satConcs;
                    model.(elde).thetaMaxs                = thetaMaxs;
                    model.(elde).thetaMins                = thetaMins;
                    model.(elde).volumes                  = vs;
                    model.(elde).computeOCPs              = computeOCPs;
                    
                end
                
            end
            
        end
        
        function [initstate, model] = setupInitialState(model)
            
        % We use a fully discharge charge battery

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            nam = model.(ne).numberOfActiveMaterial;
            if nam > 1
                for iam = 1 : nam
                    inistate.(ne).stoichiometries{iam} = model.(ne).thetaMins(iam);
                end
            else
                inistate.(ne).stoichiometries = model.(ne).thetaMins;
            end

            nam = model.(pe).numberOfActiveMaterial;
            if nam > 1
                for iam = 1 : nam
                    inistate.(pe).stoichiometries{iam} = model.(pe).thetaMaxs(iam);
                end
            else
                inistate.(pe).stoichiometries = model.(pe).thetaMaxs;
            end

            initstate = model.evalVarName(inistate, {'totalAmount'});
            
            model.totalAmount = initstate.totalAmount;
            
        end
        
        
        function model = registerVarAndPropfuncNames(model)

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            eldes = {ne, pe};

            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};

                nam = model.(elde).numberOfActiveMaterial;
                
                varnames = {};

                varnames{end + 1} = VarName({elde}, 'stoichiometries', nam);
                varnames{end + 1} = VarName({elde}, 'concentrations', nam);
                varnames{end + 1} = VarName({elde}, 'ocps', nam);
                if nam > 1
                    varnames{end + 1} = VarName({elde}, 'potentialEquations', nam - 1);
                end

                model = model.registerVarNames(varnames);
                
            end

            varnames = {};

            varnames{end + 1} = 'massConsEq';
            varnames{end + 1} = 'totalAmount';
            varnames{end + 1} = 'voltageEquation';

            model = model.registerVarNames(varnames);
            
            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};

                nam = model.(elde).numberOfActiveMaterial;

                fn = @EquilibriumConcentrationSolver.updateConcentrations;
                inputvarnames  = {VarName({elde}, 'stoichiometries', nam)};
                outputvarnames = VarName({elde}, 'concentrations', nam);
                model = model.registerPropFunction({outputvarnames, fn, inputvarnames});

                fn = @EquilibriumConcentrationSolver.updateOCPs;
                inputvarnames  = {VarName({elde}, 'concentrations', nam)};
                outputvarnames = VarName({elde}, 'ocps', nam);
                model = model.registerPropFunction({outputvarnames, fn, inputvarnames});

                if nam > 1
                    fn = @EquilibriumConcentrationSolver.updatePotentialEquation;
                    inputvarnames  = {VarName({elde}, 'ocps', nam)};
                    outputvarnames = VarName({elde}, 'potentialEquations', nam - 1);
                    model = model.registerPropFunction({outputvarnames, fn, inputvarnames});
                end

            end

            nam_ne = model.(ne).numberOfActiveMaterial;
            nam_pe = model.(pe).numberOfActiveMaterial;
            
            fn = @ConcentrationSolve.updateVoltageEquation;
            inputnames = {VarName({ne}, 'ocps', nam_ne), ...
                          VarName({pe}, 'ocps', nam_pe)};
            model = model.registerPropFunction({'voltageEquation', fn, inputnames});
            
            fn = @ConcentrationSolve.updateTotalAmount;
            inputnames = {VarName({ne}, 'concentrations', nam_ne), ...
                          VarName({pe}, 'concentrations', nam_pe)};
            model = model.registerPropFunction({'totalAmount', fn, inputnames});

            fn = @ConcentrationSolve.updateMassConsEq;
            inputnames = {'totalAmount'};
            model = model.registerPropFunction({'massConsEq', fn, inputnames});

        end
        

        function state = updateConcentrations(model, state)

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            eldes = {ne, pe};

            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};

                nam = model.(elde).numberOfActiveMaterial;

                if nam > 1
                    for iam = 1 : nam
                        state.(elde).concentrations{iam} = model.(elde).saturationConcentrations(iam)*state.(elde).stoichiometries{iam};
                    end
                else
                    state.(elde).concentrations = model.(elde).saturationConcentrations*state.(elde).stoichiometries;
                end
            end

        end

        
        function state = updateOCPs(model, state)

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            eldes = {ne, pe};

            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};

                nam = model.(elde).numberOfActiveMaterial;

                concs = state.(elde).concentrations;
                
                nam = model.(elde).numberOfActiveMaterial;

                if nam > 1
                    for iam = 1 : nam

                    ocpfunc = model.(elde).computeOCPs{iam};
                    ocps{iam} = ocpfunc(concs{iam});
                    end
                else
                    ocpfunc = model.(elde).computeOCPs{1};
                    ocps = ocpfunc(concs);
                end

                state.(elde).ocps = ocps;

            end        

        end

        
        function state = updatePotentialEquation(model, state)

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            eldes = {ne, pe};

            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};

                nam = model.(elde).numberOfActiveMaterial;

                ocps = state.(elde).ocps;

                for iam = 1 : (nam - 1)
                    
                    state.(elde).potentialEquations{iam} = ocps{iam + 1} - ocps{1};
                    
                end

            end        
            
        end

        function state = updateVoltageEquation(model, state)
            
            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';
            
            eldes = {ne, pe};            

            veq = 0*state.(ne).concentrations{1}; % dummy AD initialisation

            nam = model.(pe).numberOfActiveMaterial;

            if nam > 1
                veq = veq + state.(pe).ocps{1};
            else
                veq = veq + state.(pe).ocps;
            end
            
            nam = model.(ne).numberOfActiveMaterial;

            if nam > 1
                veq = veq - state.(ne).ocps{1};
            else
                veq = veq - state.(ne).ocps;
            end
            
            
            veq = veq - model.voltage;

            state.voltageEquation = veq;

        end
        
        function state = updateTotalAmount(model, state)
            
            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            totalAmount = 0*state.(ne).concentrations{1}; % dummy AD initialization

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            eldes = {ne, pe};
            
            for ielde = 1 : numel(eldes)
                
                elde = eldes{ielde};

                nam = model.(elde).numberOfActiveMaterial;

                if nam > 1
                    for iam = 1 : nam
                        totalAmount = totalAmount + sum(state.(elde).concentrations{iam}*model.(elde).volumes(iam));
                    end
                else
                    totalAmount = totalAmount + sum(state.(elde).concentrations*model.(elde).volumes);
                end
                
            end
            
            state.totalAmount = totalAmount;

        end
        
        function state = updateMassConsEq(model, state)
            
            state.massConsEq = state.totalAmount - model.totalAmount;

        end

        function cleanState = addStaticVariables(model, cleanState, state)
        % nothing to do here
        end

        function [state, report] = updateState(model, state, problem, dx, forces)

            [state, report] = updateState@BaseModel(model, state, problem, dx, forces);
            
            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            eldes = {ne, pe};
            
            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};
                for iam = 1 : model.(elde).numberOfActiveMaterial
                    state = model.capProperty(state, {elde, 'stoichiometries', iam}, model.(elde).thetaMins(iam), model.(elde).thetaMaxs(iam));
                end

            end
            
        end

        function plotOCPs(model, fig)

            if nargin > 1
                figure(fig)
            else
                figure
            end
            
            hold on

            ne = 'NegativeElectrode';
            pe = 'PositiveElectrode';

            eldes = {ne, pe};


            for ielde = 1 : numel(eldes)

                s1 = linspace(0, 1, 100);

                elde = eldes{ielde};
                nam = model.(elde).numberOfActiveMaterial;
                
                state1.(elde).stoichiometries = s1

            end
            for ielde = 1 : numel(eldes)

                elde = eldes{ielde};

                nam = model.(elde).numberOfActiveMaterial;
                
                for iam = 1 : nam
                    ocpfunc = model.(elde).computeOCPs{iam};

                    c = linspace(0, model.(elde).satConcs(iam));
                    v = ocpfunc(c);

                    plot(c, v);

                    c = linspace(model.(elde).thetaMins(iam), model.(elde).thetaMaxs(iam));
                    v = ocpfunc(c);

                    plot(c, v);
                    
                end

            end
            
            
        end
        
        function [state, failure, model] = computeConcentrations(model, voltage)

            model.voltage = voltage;
            [initstate, model] = setupInitialState(model);

            nls = NonLinearSolver();
            
            [state, failure, report] = nls.solveMinistep(model, initstate, initstate, [], []);

        end

        
    end

end
