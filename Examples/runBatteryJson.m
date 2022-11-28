function  output = runBatteryJson(jsonstruct, varargin)
    
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

    paramobj = BatteryInputParams(jsonstruct);

    paramobj = paramobj.validateInputParams();

    switch jsonstruct.Geometry.case

      case '1D'

        gen = BatteryGenerator1D();
        
        xlength = gen.xlength;
        xlength(2) = jsonstruct.NegativeElectrode.ActiveMaterial.thickness;
        xlength(3) = jsonstruct.Electrolyte.Separator.thickness;
        xlength(4) = jsonstruct.PositiveElectrode.ActiveMaterial.thickness;
        gen.xlength = xlength;

        gen.sepnx  = jsonstruct.NegativeElectrode.ActiveMaterial.N;
        gen.nenx   = jsonstruct.Electrolyte.Separator.N;
        gen.penx   = jsonstruct.PositiveElectrode.ActiveMaterial.N;
        
        gen.faceArea = jsonstruct.Geometry.faceArea;
        
        % Now, we update the paramobj with the properties of the mesh. 
        paramobj = gen.updateBatteryInputParams(paramobj);

      case {'2D-demo', '3d-demo'}

        error('not yet implemented');

      case 'jellyRoll'

        % Prepare input for SpiralBatteryGenerator.updateBatteryInputParams using json input
        
        widthDict = containers.Map()
        widthDict('ElectrolyteSeparator')     = jsonstuct.Electrolyte.Separator.thickness;
        widthDict('NegativeActiveMaterial')   = jsonstruct.NegativeElectrode.ActiveMaterial.thickness;
        widthDict('NegativeCurrentCollector') = jsonstruct.NegativeElectrode.CurrentCollector.thickness;
        widthDict('PositiveActiveMaterial')   = jsonstruct.PositiveElectrode.ActiveMaterial.thickness;
        widthDict('PositiveCurrentCollector') = jsonstruct.PositiveElectrode.CurrentCollector.thickness;
        
        nwidths = [widthDict('PositiveActiveMaterial');...
                   widthDict('PositiveCurrentCollector');...
                   widthDict('PositiveActiveMaterial');...
                   widthDict('ElectrolyteSeparator');...
                   widthDict('NegativeActiveMaterial');...
                   widthDict('NegativeCurrentCollector');...
                   widthDict('NegativeActiveMaterial');...
                   widthDict('ElectrolyteSeparator')]; 
        dr = sum(nwidths);
        
        rOuter = jsonstruct.Geometry.rOuter;
        rInner = jsonstruct.Geometry.rInner;
        L      = jsonstruct.Geometry.L;
        nL     = jsonstruct.Geometry.nL;
        nas    = jsonstruct.Geometry.nas;

        tabparams = jsonstruct.Geometry.tabparams;

        nrDict = containers.Map()
        nrDict('ElectrolyteSeparator')     = jsonstuct.Electrolyte.Separator.N;
        nrDict('NegativeActiveMaterial')   = jsonstruct.NegativeElectrode.ActiveMaterial.N;
        nrDict('NegativeCurrentCollector') = jsonstruct.NegativeElectrode.CurrentCollector.N;
        nrDict('PositiveActiveMaterial')   = jsonstruct.PositiveElectrode.ActiveMaterial.N;
        nrDict('PositiveCurrentCollector') = jsonstruct.PositiveElectrode.CurrentCollector.N;

        % compute numbers of winding (this is input for spiralGrid) from outer and inner radius
        nwidths = [widthDict('PositiveActiveMaterial');...
                   widthDict('PositiveCurrentCollector');...
                   widthDict('PositiveActiveMaterial');...
                   widthDict('ElectrolyteSeparator');...
                   widthDict('NegativeActiveMaterial');...
                   widthDict('NegativeCurrentCollector');...
                   widthDict('NegativeActiveMaterial');...
                   widthDict('ElectrolyteSeparator')]; 
        dr = sum(nwidths);dR = rOuter - rInner; 
        % Computed number of windings
        nwindings = ceil(dR/dr);
        
        spiralparams = struct('nwindings'   , nwindings, ...
                              'rInner'      , rInner   , ...
                              'widthDict'   , widthDict, ...
                              'nrDict'      , nrDict   , ...
                              'nas'         , nas      , ...
                              'L'           , L        , ...
                              'nL'          , nL       , ...
                              'tabparams'   , tabparams, ...
                              'angleuniform', true); 
        
        gen = SpiralBatteryGenerator(); 
        paramobj = gen.updateBatteryInputParams(paramobj, spiralparams);

      otherwise
        
        error('Geometry case not recognized')
        
    end
    

    %%  Initialize the battery model. 
    % The battery model is initialized by sending paramobj to the Battery class
    % constructor. see :class:`Battery <Battery.Battery>`.

    model = Battery(paramobj);
    model.AutoDiffBackend= AutoDiffBackend();


    %% Compute the nominal cell capacity and choose a C-Rate
    % The nominal capacity of the cell is calculated from the active materials.
    % This value is then combined with the user-defined C-Rate to set the cell
    % operational current. 

    CRate = model.Control.CRate;

    %% Setup the time step schedule


    total = jsonstruct.TimeStepping.totalTime;
    n = jsonstruct.TimeStepping.N;

    dt = total/n;
    
    step = struct('val', dt*ones(n, 1), 'control', ones(n, 1));

    % we setup the control by assigning a source and stop function.
    % control = struct('CCCV', true); 
    %  !!! Change this to an entry in the JSON with better variable names !!!

    switch model.Control.controlPolicy
      case 'IEswitch'
        tup = 0.1; % rampup value for the current function, see rampupSwitchControl
        srcfunc = @(time, I, E) rampupSwitchControl(time, tup, I, E, ...
                                                    model.Control.Imax, ...
                                                    model.Control.lowerCutoffVoltage);
        % we setup the control by assigning a source and stop function.
        control = struct('src', srcfunc, 'IEswitch', true);
      case 'CCCV'
        control = struct('CCCV', true);
      otherwise
        error('control policy not recognized');
    end

    % This control is used to set up the schedule
    schedule = struct('control', control, 'step', step); 

    %% Setup the initial state of the model
    % The initial state of the model is setup using the model.setupInitialState() method.

    if isfield(jsonstruct, 'initializationSetup')
        initializationSetup = jsonstruct.initializationSetup;
    else
        % default is given SOC
        initializationSetup = "given SOC";
    end
    
    switch initializationSetup
      case "given SOC"
        initstate = model.setupInitialState();
      case "given input"
        error('interface not yet implemented');
      otherwise
        error('initializationSetup not recognized');
    end
    
    
    %% Setup the properties of the nonlinear solver 
    nls = NonLinearSolver();

    % Change default maximum iteration number in nonlinear solver
    nls.maxIterations = 10;
    % Change default behavior of nonlinear solver, in case of error
    nls.errorOnFailure = false;
    nls.timeStepSelector=StateChangeTimeStepSelector('TargetProps', {{'Control','E'}}, 'targetChangeAbs', 0.03);
    % Change default tolerance for nonlinear solver
    model.nonlinearTolerance = 1e-3*model.Control.Imax;
    % Set verbosity
    model.verbose = false;

    %% Run the simulation
    [~, states, report] = simulateScheduleAD(initstate, model, schedule, 'OutputMinisteps', true, 'NonLinearSolver', nls); 

    %% Process output and recover the output voltage and current from the output states.
    ind = cellfun(@(x) not(isempty(x)), states); 
    states = states(ind);
    
    E    = cellfun(@(state) state.Control.E, states); 
    I    = cellfun(@(state) state.Control.I, states);
    time = cellfun(@(state) state.time, states); 

    output = struct('model', model, ...
                    'time' , time , ... % Unit : s
                    'E'    , E    , ... % Unit : V
                    'I'    , I); ... % Unit : A

    output.states = states;
    
    if isfield(jsonstruct, 'Output') && any(strcmp({"energyDensity", "specificEnergy"}, jsonstruct.Output))
        
        % We could fine tuned output
        mass = computeCellMass(model);
        vol = sum(model.G.cells.volumes);
        
        [E, I, energyDensity, specificEnergy, energy] = computeEnergyDensity(E, I, time, vol, mass);

        output.E              = E;
        output.I              = I;
        output.energy         = energy;          % Unit : J
        output.energyDensity  = energyDensity;   % Unit : J/L
        output.specificEnergy = specificEnergy;  % Unit : J/kg
        
    end

end
