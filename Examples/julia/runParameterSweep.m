clear

%% Setup Julia server

man = ServerManager('debug', false, 'procs', 8);

% Set up keyword arguments to be sent to julia solver. See run_battery in mrst_utils.jl for details
kwargs = struct('use_p2d'     , true , ...
                'extra_timing', false, ...
                'general_ad'  , true);

%% Pick source JSON files for generating model

%JSON file cases
casenames = {'p1d_40',
             'p2d_40'};
casenames = casenames{2};

% casenames = {'3d_demo_case'};
% casenames = {'4680_case'};

% JSON file folder

battmo_folder = battmoDir();
jsonfolder    = fullfile(battmo_folder, 'Examples', 'julia', 'jsonfiles');

%% Setup model from Matlab

testCase = 'JSON';

switch testCase

  case 'Matlab'

    % If true a reference solution will be generated.
    generate_reference_solution = true;
    export = setupMatlabModel(casenames, jsonfolder, generate_reference_solution);

    man.load('data'         , export  , ...
             'kwargs'       , kwargs  , ...
             'inputType'    , 'Matlab', ...
             'use_state_ref', generate_reference_solution);

  case 'JSON'

    generate_reference_solution = false;
    inputFileName = fullfile(jsonfolder, 'p2d_40_jl.json');

    man.load('kwargs'       , kwargs, ...
             'inputType'    , 'JSON', ...
             'inputFileName', inputFileName);

  otherwise

    error('testCase not recognized');

end

%This must only be defined ONCE. Must be manually deleted before clear all

%%
v = linspace(0.7, 0.9, 20);
f = man.sweep('Example', {v , v}, 'demo');

%%
ind = [1, 20, 300];
start = tic;
res = man.collect_results(f, ind);
toc(start)

%% Plot results

figure()
% Results generated by BattMo.jl

for i = 1:length(ind)
    E = arrayfun(@(state) state.Control.E, res(i).states.matlabStates);
    time = arrayfun(@(state) state.time, res(i).states.matlabStates);
    plot(time, E, 'DisplayName', strcat('Parameters=(', num2str(res(i).parameters(1)), ',', num2str(res(i).parameters(2)), ')'), LineWidth=2)
    hold on
end

if generate_reference_solution
    hold on
    E = cellfun(@(state) state.Control.E, export.states);
    time = cellfun(@(state) state.time, export.states);
    plot(time, E, 'DisplayName', 'BattMo Matlab', LineWidth=2, LineStyle='--')
end

legend
grid on
