function  output = runBatteryJson(jsonstruct, varargin)

    opt = struct('runSimulation'       , true , ...
                 'includeGridGenerator', false, ...
                 'validateJson'        , false);
    opt = merge_options(opt, varargin{:});

    mrstModule add ad-core mrst-gui mpfa

    % We define some shorthand names for simplicity.
    ne      = 'NegativeElectrode';
    pe      = 'PositiveElectrode';
    elyte   = 'Electrolyte';
    thermal = 'ThermalModel';
    am      = 'ActiveMaterial';
    itf     = 'Interface';
    sd      = 'SolidDiffusion';
    ctrl    = 'Control';
    cc      = 'CurrentCollector';

    %% Validate
    if opt.validateJson
        validateJsonStruct(jsonstruct);
    end

    %%  Initialize the battery model.
    % The battery model is setup using :battmo:`setupModelFromJson`

    [model, inputparams, jsonstruct, gridGenerator] = setupModelFromJson(jsonstruct);

    %% model parameter required for initialization if initializationSetup = "given SOC";
    % The initial state of the model is setup using the model.setupInitialState() method.

    if isfield(jsonstruct, 'initializationSetup')
        initializationSetup = jsonstruct.initializationSetup;
    else
        % default is given SOC
        initializationSetup = "given SOC";
    end

    switch initializationSetup
      case "given SOC"
        inputparams.initT = jsonstruct.initT;
        inputparams.SOC   = jsonstruct.SOC;
      case "given input"
        eval(jsonstruct.loadStateCmd);
      otherwise
        error('initializationSetup not recognized');
    end

    %% Compute the nominal cell capacity and choose a C-Rate
    % The nominal capacity of the cell is calculated from the active materials.
    % This value is then combined with the user-defined C-Rate to set the cell
    % operational current.

    CRate = model.Control.CRate;

    %% Setup the time step schedule
    %

    if isfield(jsonstruct, 'TimeStepping')
        timeSteppingParams = jsonstruct.TimeStepping;
    else
        timeSteppingParams = [];
    end

    step    = model.(ctrl).setupScheduleStep(timeSteppingParams);
    control = model.(ctrl).setupScheduleControl();

    % This control is used to set up the schedule
    schedule = struct('control', control, 'step', step);

    switch initializationSetup
      case "given SOC"
        if isfield(jsonstruct, 'Electrolyte') && isfield(jsonstruct.Electrolyte, 'initialConcentration')
            jsonstructInit.Electrolyte.initialConcentration = jsonstruct.Electrolyte.initialConcentration;
        else
            jsonstructInit = [];
        end
        initstate = model.setupInitialState(jsonstructInit);
      case "given input"
        % allready handled
      otherwise
        error('initializationSetup not recognized');
    end

    [model, nls] = setupNonLinearSolverFromJson(model, jsonstruct);

    %% Run the simulation
    %

    if opt.runSimulation

        if isfield(jsonstruct, 'Output') && isfield(jsonstruct.Output, 'saveOutput') && jsonstruct.Output.saveOutput
            saveOptions = jsonstruct.Output.saveOptions;

            outputDirectory = saveOptions.outputDirectory;
            name            = saveOptions.name;
            clearSimulation = saveOptions.clearSimulation;

            problem = packSimulationProblem(initstate, model, schedule, [], ...
                                            'Directory'      , outputDirectory, ...
                                            'Name'           , name      , ...
                                            'NonLinearSolver', nls);
            problem.SimulatorSetup.OutputMinisteps = true;

            if clearSimulation
                %% clear previously computed simulation
                clearPackedSimulatorOutput(problem, 'prompt', false);
            end
            simulatePackedProblem(problem);
            [globvars, states, reports] = getPackedSimulatorOutput(problem);

        else
            [~, states, report] = simulateScheduleAD(initstate, model, schedule, 'OutputMinisteps', true, 'NonLinearSolver', nls);
        end
    else
        output = struct('model'    , model    , ...
                        'inputparams' , inputparams , ...
                        'schedule' , schedule , ...
                        'initstate', initstate);
        if opt.includeGridGenerator
            output.gridGenerator = gridGenerator;
        end

        return;
    end

    %% Process output and recover the output voltage and current from the output states.
    ind = cellfun(@(x) not(isempty(x)), states);
    states = states(ind);

    E    = cellfun(@(state) state.Control.E, states);
    I    = cellfun(@(state) state.Control.I, states);
    time = cellfun(@(state) state.time, states);

    output = struct('model'    , model    , ...
                    'inputparams' , inputparams , ...
                    'schedule' , schedule , ...
                    'initstate', initstate, ...
                    'time'     , time     , ... % Unit : s
                    'E'        , E        , ... % Unit : V
                    'I'        , I); ... % Unit : A

    output.states = states;

    if isfield(jsonstruct, 'Output') ...
        && isfield(jsonstruct.Output, 'variables') ...
        && any(ismember({'energy', 'energyDensity', 'specificEnergy'}, jsonstruct.Output.variables))

        if ismember('specificEnergy', jsonstruct.Output.variables)
            mass = computeCellMass(model);
        else
            mass = [];
        end
        vol = sum(model.G.cells.volumes);

        [E, I, energyDensity, specificEnergy, energy] = computeEnergyDensity(E, I, time, vol, mass);

        output.E              = E;
        output.I              = I;
        output.energy         = energy;          % Unit : J
        output.energyDensity  = energyDensity;   % Unit : J/L
        output.specificEnergy = specificEnergy;  % Unit : J/kg

    end

    if opt.includeGridGenerator
        output.gridGenerator = gridGenerator;
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
