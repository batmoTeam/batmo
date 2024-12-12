% Clear the workspace and close open figures
clear
close all

%% Import the required modules from MRST
% load MRST modules

mrstModule add ad-core mrst-gui mpfa agmg linearsolvers

%% Setup the properties of Li-ion battery materials and cell design
% The properties and parameters of the battery cell, including the
% architecture and materials, are set using an instance of
% :class:`BatteryInputParams <Battery.BatteryInputParams>`. This class is
% used to initialize the simulation and it propagates all the parameters
% throughout the submodels. The input parameters can be set manually or
% provided in json format. All the parameters for the model are stored in
% the inputparams object.

% The input parameters can be given in json format. The json file is read and used to populate the inputparams object.
jsonstruct_material = parseBattmoJson(fullfile('ParameterData','ParameterSets','Chen2020','chen2020_lithium_ion_battery.json'));
jsonstruct_geometry = parseBattmoJson(fullfile('Examples', 'JsonDataFiles', 'geometryChen.json'));

jsonstruct_control = parseBattmoJson(fullfile('Examples', 'JsonDataFiles', 'flat_generic_step_control.json'));
jsonstruct_material = removeJsonStructFields(jsonstruct_material, ...
    {'Control', 'DRate'}        , ...
    {'Control', 'controlPolicy'}, ...
    {'Control', 'upperCutoffVoltage'}    , ...
    {'Control', 'dIdtLimit'}    , ...
    {'Control', 'rampupTime'}   , ...
    {'Control', 'lowerCutoffVoltage'});

jsonstruct = mergeJsonStructs({jsonstruct_material, ...
    jsonstruct_geometry, jsonstruct_control});

% We define some shorthand names for simplicity.
ne      = 'NegativeElectrode';
pe      = 'PositiveElectrode';
elyte   = 'Electrolyte';
thermal = 'ThermalModel';
co      = 'Coating';
am      = 'ActiveMaterial';
itf     = 'Interface';
sd      = 'SolidDiffusion';
ctrl    = 'Control';
cc      = 'CurrentCollector';

jsonstruct.use_thermal = false;
jsonstruct.include_current_collectors = false;

inputparams = BatteryInputParams(jsonstruct);

%% We setup the battery geometry ("bare" battery with no current collector).

[inputparams, gen] = setupBatteryGridFromJson(inputparams, jsonstruct);

%%  The Battery model is initialized by sending inputparams to the Battery class constructor

model = GenericBattery(inputparams);

timestep.timeStepDuration = 100;

step    = model.Control.setupScheduleStep(timestep);
control = model.Control.setupScheduleControl();

% This control is used to set up the schedule
schedule = struct('control', control, 'step', step);

%% Setup the initial state of the model
% The initial state of the model is setup using the model.setupInitialState() method.

initstate = model.setupInitialState();

%% Run the simulation
[~, states, report] = simulateScheduleAD(initstate, model, schedule, 'OutputMinisteps', true);
% output = runBatteryJson(jsonstruct);

%% Process output and recover the output voltage and current from the output states.
ind = cellfun(@(x) not(isempty(x)), states);
states = states(ind);
E = cellfun(@(x) x.Control.E, states);
I = cellfun(@(x) x.Control.I, states);
T = cellfun(@(x) max(x.(thermal).T), states);
Tmax = cellfun(@(x) max(x.ThermalModel.T), states);
% [SOCN, SOCP] =  cellfun(@(x) model.calculateSOC(x), states);
time = cellfun(@(x) x.time, states);

figure
plot(time/hour, E, '*-');
grid on
xlabel 'time  / h';
ylabel 'potential  / V';

figure
plot(time/hour, I, '*-');
grid on
xlabel 'time  / h';
ylabel 'Current  / A';