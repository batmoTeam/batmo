%% Pseudo-Four-Dimensional (P4D) Lithium-Ion Battery Model
% This example demonstrates how to setup a P4D model of a Li-ion battery
% and run a simple simulation.

% Clear the workspace and close open figures
clear
close all

%% Import the required modules from MRST
% load MRST modules
mrstModule add ad-core mrst-gui mpfa

%% Setup the properties of Li-ion battery materials and cell design
% The properties and parameters of the battery cell, including the
% architecture and materials, are set using an instance of
% :class:`BatteryInputParams <Battery.BatteryInputParams>`. This class is
% used to initialize the simulation and it propagates all the parameters
% throughout the submodels. The input parameters can be set manually or
% provided in json format. All the parameters for the model are stored in
% the paramobj object.
jsonstruct = parseBattmoJson(fullfile('ParameterData','BatteryCellParameters','LithiumIonBatteryCell','lithium_ion_battery_nmc_graphite.json'));
jsonstruct.include_current_collectors = true;

paramobj = BatteryInputParams(jsonstruct);


% We define some shorthand names for simplicity.
ne      = 'NegativeElectrode';
pe      = 'PositiveElectrode';
am      = 'ActiveMaterial';
cc      = 'CurrentCollector';
elyte   = 'Electrolyte';
thermal = 'ThermalModel';
ctrl    = 'Control';

%% Setup the geometry and computational grid
% Here, we setup the 3D computational grid that will be used for the
% simulation. The required discretization parameters are already included
% in the class BatteryGeneratorP4D.
gen = BatteryGeneratorP4D();

% Now, we update the paramobj with the properties of the grid.
paramobj = gen.updateBatteryInputParams(paramobj);

%%  Initialize the battery model.
% The battery model is initialized by sending paramobj to the Battery class
% constructor. see :class:`Battery <Battery.Battery>`.

model = Battery(paramobj);

%% Setup the time step schedule
% Smaller time steps are used to ramp up the current from zero to its
% operational value. Larger time steps are then used for the normal
% operation.

timestep.numberOfTimeSteps = 50;
timestep.useRampup = true;

step = model.(ctrl).setupScheduleStep(timestep);

%% Setup the operating limits for the cell
% The maximum and minimum voltage limits for the cell are defined using
% stopping and source functions. A stopping function is used to set the
% lower voltage cutoff limit. A source function is used to set the upper
% voltage cutoff limit.

% we setup the control by assigning a source and stop function.
control = model.(ctrl).setupScheduleControl();

% This control is used to set up the schedule
schedule = struct('control', control, 'step', step);

%% Setup the initial state of the model
% The initial state of the model is dispatched using the
% model.setupInitialState()method.
initstate = model.setupInitialState();

%% Setup the properties of the nonlinear solver
nls = NonLinearSolver();
% Change default maximum iteration number in nonlinear solver
nls.maxIterations = 10;
% Change default behavior of nonlinear solver, in case of error
nls.errorOnFailure = false;
% Timestep selector
nls.timeStepSelector = StateChangeTimeStepSelector('TargetProps', ...
                                                  {{ctrl, 'E'}}, ...
                                                  'targetChangeAbs', 0.03);

% Change default tolerance for nonlinear solver
model.nonlinearTolerance = 1e-5;
% Set verbosity of the solver (if true, value of the residuals for every equation is given)
model.verbose = false;

%% Run simulation
[~, states, report] = simulateScheduleAD(initstate, model, schedule, 'OutputMinisteps', true, 'NonLinearSolver', nls);

%%  Process output and recover the output voltage and current from the output states.
ind = cellfun(@(x) not(isempty(x)), states);
states = states(ind);
E = cellfun(@(x) x.(ctrl).E, states);
I = cellfun(@(x) x.(ctrl).I, states);
time = cellfun(@(x) x.time, states);

figure
plot(time/hour, E);
grid on
xlabel 'time  / h';
ylabel 'potential  / V';

%% Plot an animated summary of the results
doplot = false;
if doplot
    plotDashboard(model, states, 'step', 0);
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
