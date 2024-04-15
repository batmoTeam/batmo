% clear all

% mrstDebug(20);

mrstModule add ad-core mrst-gui

gs    = 'GasSupply';
ce    = 'Cell';
an    = 'Anode';
ct    = 'Cathode';
elyte = 'Electrolyte';
ctrl  = 'Control';
            
clear jsonstruct

filename = 'ProtonicMembrane/gas_supply_whole_cell.json';
jsonstruct.GasSupply = parseBattmoJson(filename);
filename = 'ProtonicMembrane/protonicMembrane.json';
jsonstruct.Cell = parseBattmoJson(filename);

%% Adjust diffusion

Dmult = 1e-3;
fprintf('Diffusion coefficient multiplier : %g\n', Dmult);
jsonstruct.(gs).diffusionCoefficients = Dmult*jsonstruct.(gs).diffusionCoefficients;

%%

inputparams = ProtonicMembraneCellWithGasSupplyInputParams(jsonstruct);

gen = GasSupplyPEMgridGenerator2D();

gen.nxCell      = 1000;
gen.nxGasSupply = 50;
gen.lxCell      = 22*micro*meter;
gen.lxGasSupply = 0.5*milli*meter;

gen.ny = 30;
gen.ly = 1.5e-3;

inputparams = gen.updateInputParams(inputparams);

doplot = false;

if doplot
    
    close all

    figure('position', [337, 757, 3068, 557])
    plotGrid(inputparams.G)
    plotGrid(inputparams.Cell.G, 'facecolor', 'red')
    plotGrid(inputparams.GasSupply.G, 'facecolor', 'blue')

    plotGrid(inputparams.GasSupply.G, inputparams.GasSupply.couplingTerms{1}.couplingcells);
    plotGrid(inputparams.GasSupply.G, inputparams.GasSupply.couplingTerms{2}.couplingcells);
    plotGrid(inputparams.Cell.G, inputparams.Cell.couplingTerms{1}.couplingcells(:, 2));
    plotGrid(inputparams.Cell.G, inputparams.Cell.couplingTerms{2}.couplingcells(:, 2));
    plotGrid(inputparams.GasSupply.G, inputparams.GasSupply.couplingTerms{3}.couplingcells );

    return
    
end

%% Adjust Imax

Imax = 0.5/((centi*meter)^2) * gen.ly;
fprintf('use Imax = %g\n', Imax);

%%

rungaslayer = false;

if rungaslayer

    filename = 'ProtonicMembrane/gas_supply_whole_cell.json';
    gsjsonstruct = parseBattmoJson(filename);

    %% adjust N2
    h2omassfracoutput = 0.4
    fprintf('use H2O mass fraction at output  = %g\n', h2omassfracoutput);
    gsjsonstruct.control(2).values(2) = h2omassfracoutput;
    %%
    
    gsinputparams = ProtonicMembraneGasSupplyInputParams(gsjsonstruct);

    gsgen = GasSupplyGridGenerator2D();

    gsgen.nx = gen.nxGasSupply;
    gsgen.ny = gen.ny;
    gsgen.lx = gen.lxGasSupply;
    gsgen.ly = gen.ly;
    
    gsinputparams = gsgen.updateInputParams(gsinputparams);

    gsmodel = ProtonicMembraneGasSupply(gsinputparams);
    gsmodel = gsmodel.setupForSimulation();

    initstate = gsmodel.setupInitialState();

    %% setup scalings

    gasInd = gsmodel.gasInd;

    pH2O         = initstate.pressure(1);
    rho          = initstate.density(1);
    scalFlux     = 1/gsgen.nx*(rho*gsmodel.permeability/gsmodel.viscosity*pH2O + rho*gsmodel.diffusionCoefficients(1))/gsgen.ly;
    scalPressure = pH2O;
    
    gsmodel.scalings = {{{'massConses', 1}, scalFlux}, ...
                      {{'massConses', 2}, scalFlux}, ...
                      {{'Control', 'pressureEq'}, scalPressure}, ...
                      {{'Control', 'rateEq'}, gsgen.nx*scalFlux}, ...
                      {{'GasSupplyBc', 'bcFluxEquations', 1}, scalFlux}, ...
                      {{'GasSupplyBc', 'bcFluxEquations', 2}, scalFlux}};


    T = 1*second;
    N = 1;
    dt = rampupTimesteps(T, T/N, 10, 'threshold_error', 1e-15);

    step.val = dt;
    step.control = ones(numel(step.val), 1);

    control.src = [];

    schedule = struct('control', control, 'step', step);

    nls = NonLinearSolver();
    nls.maxIterations = 20;
    nls.errorOnFailure = false;
    nls.verbose = true;

    gsmodel.verbose = true;

    gsmodel.nonlinearTolerance = 1e-8;

    [~, gsstates, report] = simulateScheduleAD(initstate, gsmodel, schedule, 'OutputMinisteps', true, 'NonLinearSolver', nls);

    %%

    figure
    plotToolbar(gsmodel.grid, gsstates);
    % caxis([0.2, 0.4])
    % uit = findobj(gcf, 'Tooltip', 'Freeze caxis');
    % uit.State = 'on';

    return
    
end

%%

doinitialisation = false;

if doinitialisation
    % We run the protonic membrane alone to get an order of magnitude of iHp to scale the full cell model (with gas
    % layer)

    filename = 'ProtonicMembrane/protonicMembrane.json';
    jsonstructpem = parseBattmoJson(filename);

    inputparamspem = ProtonicMembraneCellInputParams(jsonstructpem);

    genpem = PEMgridGenerator2D();
    genpem.xlength = gen.lxCell;
    genpem.ylength = gen.ly;
    genpem.Nx      = gen.nxCell;
    genpem.Ny      = gen.ny;

    inputparamspem = genpem.updateInputParams(inputparamspem);

    model = ProtonicMembraneCell(inputparamspem);
    
    model = model.setupForSimulation();
    
    state0 = model.setupInitialState();

    tswitch = 1;
    T       = 2; % This is not a real time scale, as all the model deals with equilibrium

    N1  = 20;
    dt1 = tswitch/N1;
    N2  = 20;
    dt2 = (T - tswitch)/N2;

    step.val = [dt1*ones(N1, 1); dt2*ones(N2, 1)];
    step.control = ones(numel(step.val), 1);

    % Imax = 1e-2*ampere/((centi*meter)^2);
    % Imax = 0.3*ampere/((centi*meter)^2);
    % Imax = 0.01*ampere/((centi*meter)^2);
    control.src = @(time) controlfunc(time, Imax, tswitch, T, 'order', 'I-first');

    schedule = struct('control', control, 'step', step); 
    nls = NonLinearSolver();
    nls.maxIterations = 20;
    nls.errorOnFailure = false;
    nls.verbose = true;

    model.nonlinearTolerance = 1e-8;

    [~, states, report] = simulateScheduleAD(state0, model, schedule, 'OutputMinisteps', true, 'NonLinearSolver', nls);

    state = states{end};
    state = model.addVariables(state, drivingforces);

    molfluxref = abs(sum(state.Anode.iHp)/PhysicalConstants.F); % in mol/second

    fprinft('Reference molar flux: %g mol/second', molfluxref);
    
    return
    
else
    
    molfluxref = 1.7236e-06; % value for Imax = 0
    
end

%%

model = ProtonicMembraneCellWithGasSupply(inputparams);

model = model.setupForSimulation();

cgt = model.cgt;
cgp = model.cgp;

%% Setup initial state

initstate = model.setupInitialState();

%% Setup scalings

gasInd = model.(gs).gasInd;

pH2O         = initstate.(gs).pressure(1);
rho          = initstate.(gs).density(1);
scalFlux     = molfluxref/model.(gs).molecularWeights(1)/gen.ny; % in kg/s
scalPressure = pH2O;

model.scalings = {{{gs, 'massConses', 1}, scalFlux}                      , ...
                  {{gs, 'massConses', 2}, scalFlux}                      , ...
                  {{gs, 'Control', 'pressureEq'}, scalPressure}          , ...
                  {{gs, 'Control', 'rateEq'}, gen.nxGasSupply*scalFlux}           , ...
                  {{gs, 'GasSupplyBc', 'bcFluxEquations', 1}, scalFlux}, ...
                  {{gs, 'GasSupplyBc', 'bcFluxEquations', 2}, scalFlux}};

drivingforces.src = @(time) controlfunc(time, 0, 1, 2, 'order', 'I-first');
initstate = model.evalVarName(initstate, {ce, elyte, 'sigmaEl'}, {{'drivingForces', drivingforces}});
initstate = model.evalVarName(initstate, {ce, elyte, 'sigmaHp'}, {{'drivingForces', drivingforces}});

sigmaHp = initstate.(ce).(elyte).sigmaHp(1);
sigmaEl = initstate.(ce).(elyte).sigmaEl(1);
phi0    = abs(model.(ce).(an).E_0 - model.(ce).(ct).E_0); % characteristic voltage
T       = model.(ce).(elyte).G.getTrans();
T       = T(1);

sHp = T*sigmaHp*phi0;
sEl = T*sigmaEl*phi0;

model.scalings =  horzcat(model.scalings, ...
                          {{{ce, elyte, 'massConsHp'}     , sHp}, ...
                           {{ce, elyte, 'chargeConsEl'}   , sEl}, ...
                           {{ce, an   , 'chargeCons'}     , sEl}, ...
                           {{ce, an   , 'iElEquation'}    , sEl}, ...
                           {{ce, an   , 'iHpEquation'}    , sHp}, ...
                           {{ce, ct   , 'chargeCons'}     , sEl}, ...
                           {{ce, ct   , 'iElEquation'}    , sEl}, ...
                           {{ce, ct   , 'iHpEquation'}    , sHp}, ...
                           {{ce, ctrl , 'controlEquation'}, sEl}, ...
                           {{ce, 'anodeChargeCons'}       , sEl}});

%% Setup schedule

tswitch   = 5e-6/Dmult;
totaltime = 10*second;

%% adjust N2
N1  = 1;
fprintf('use N1 = %g\n', N1);
%%

timeswitch = tswitch*totaltime;
dt1 = timeswitch/N1;

steps1 = rampupTimesteps(timeswitch, dt1, 5);
%% adjust N2
N2  = 30;
fprintf('use N2 = %g\n', N2);

%%

dt2 = (totaltime - timeswitch);
t2  = linspace(0, dt2, N2 + 1)';
alpha = 40;
t2 = log(alpha*t2 + 1)./log(alpha*dt2 + 1)*dt2;

steps2 = diff(t2);

%%

step.val = [steps1; steps2];
step.control = ones(numel(step.val), 1);

control.src = @(time) controlfunc(time, Imax, timeswitch, totaltime, 'order', 'I-first');

schedule = struct('control', control, 'step', step); 

%% Setup nonlinear solver

nls                = NonLinearSolver();
nls.maxIterations  = 20;
nls.errorOnFailure = false;
nls.verbose        = true;

model.nonlinearTolerance = 1e-5;
model.verbose = true;

%% Start simulation

dopack = true;
clearSimulation = true;

if dopack

    name = 'testwholecell';
    problem = packSimulationProblem(initstate, model, schedule, []             , ...
                                    'ExtraArguments', {'OutputMinisteps', true}, ...
                                    'Name'           , name                    , ...
                                    'NonLinearSolver', nls);
    if clearSimulation
        %% clear previously computed simulation
        clearPackedSimulatorOutput(problem, 'prompt', false);
    end
    simulatePackedProblem(problem);
    [globvars, states, reports] = getPackedSimulatorOutput(problem);
    
else
    
    [~, states, report] = simulateScheduleAD(initstate, model, schedule, 'OutputMinisteps', true, 'NonLinearSolver', nls); 

end

%%

close all

set(0, 'defaultlinelinewidth', 3);
set(0, 'defaultaxesfontsize', 15);

N = gen.nxCell;
xc = model.(ce).(elyte).grid.cells.centroids(1 : N, 1);

state = states{end};

state = model.addVariables(state);

X = reshape(model.(ce).(elyte).grid.cells.centroids(:, 1), N, [])/(milli*meter);
Y = reshape(model.(ce).(elyte).grid.cells.centroids(:, 2), N, [])/(milli*meter);

figure
val = state.(ce).(elyte).pi;
Z = reshape(val, N, []);
surf(X, Y, Z, 'edgecolor', 'none');
title('pi')
xlabel('x [mm]')
view(45, 31)
colorbar

figure
val = state.(ce).(elyte).pi - state.(ce).(elyte).phi;
Z = reshape(val, N, []);
surf(X, Y, Z, 'edgecolor', 'none');
title('E')
xlabel('x [mm]')
view(45, 31)
colorbar

figure
val = state.(ce).(elyte).phi;
Z = reshape(val, N, []);
surf(X, Y, Z, 'edgecolor', 'none');
title('phi')
xlabel('x [mm]')
view(73, 12)
colorbar

N = gen.nxGasSupply;

X = reshape(model.(gs).grid.cells.centroids(:, 1), N, [])/(milli*meter);
Y = reshape(model.(gs).grid.cells.centroids(:, 2), N, [])/(milli*meter);

figure('position', [1290, 755, 1275, 559])

val = state.(gs).massfractions{1};
Z = reshape(val, N, []);

surf(X, Y, Z, 'edgecolor', 'none');
colorbar
title('Mass Fraction H2O');
xlabel('x [mm]')
view([50, 51]);

figure('position', [1290, 755, 1275, 559])

val = state.(gs).massfractions{2};
Z = reshape(val, N, []);

surf(X, Y, Z, 'edgecolor', 'none');
colorbar
title('Mass Fraction O2');
xlabel('x [mm]')
view([50, 51]);

figure('position', [1290, 755, 1275, 559])

val = state.(gs).pressure;
Z = reshape(val, N, []);

surf(X, Y, Z/barsa, 'edgecolor', 'none');
colorbar
title('Pressure / bar');
xlabel('x [mm]')
view([50, 51]);

figure('position', [1290, 755, 1275, 559])

val = state.(gs).density;
Z = reshape(val, N, []);

surf(X, Y, Z, 'edgecolor', 'none');
colorbar
title('Density kg/m^3');
xlabel('x [mm]')
view([50, 51]);


% Current in anode

i = state.Cell.Anode.i;

ind   = model.Cell.couplingTerms{1}.couplingfaces(:, 2);
yc    = model.Cell.Electrolyte.grid.faces.centroids(ind, 2);
areas = model.Cell.Electrolyte.grid.faces.areas(ind);

i = (i./areas)/(1/(centi*meter));

figure
plot(yc/(milli*meter), i);
title('Current in Anode / A/cm')
xlabel('height / mm')


% Current in anode

iHp = state.Cell.Anode.iHp;

ind   = model.Cell.couplingTerms{1}.couplingfaces(:, 2);
yc    = model.Cell.Electrolyte.grid.faces.centroids(ind, 2);
areas = model.Cell.Electrolyte.grid.faces.areas(ind);

iHp = (iHp./areas)/(1/(centi*meter));

figure
plot(yc/(milli*meter), iHp);
title('iHp in Anode / A/cm')
xlabel('height / mm')

% Faradic effect in Anode

drivingForces.src = @(time) controlfunc(time, Imax, timeswitch, totaltime, 'order', 'I-first');
state = model.evalVarName(state, 'Cell.Anode.iHp', {{'drivingForces', drivingForces}});

i   = state.Cell.Anode.i;
iHp = state.Cell.Anode.iHp;

ind = model.Cell.couplingTerms{1}.couplingfaces(:, 2);
yc  = model.Cell.Electrolyte.grid.faces.centroids(ind, 2);

figure
plot(yc/(milli*meter), iHp./i);
title('Faradic effect')
xlabel('height / mm')


%%

figure
plotToolbar(model.GasSupply.grid, states);

%%