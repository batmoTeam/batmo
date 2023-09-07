function [res,ode_state]=simulateScheduleode15i(initstate,model,schedule,varargin)
    %Solve semidiscrete problem using ode15i

    %% Consistency checks, copied from simulatescheduleAD in MRST
    opt = struct('Verbose',           mrstVerbose());
    % Check if model is self-consistent and set up for current BC type
    dispif(opt.Verbose, 'Validating model...\n')
    ctrl = schedule.control(schedule.step.control(1));
    [forces, ~] = model.getDrivingForces(ctrl);

    %!!!
    %model = model.validateModel(fstruct, opt.checkOperators);
    dispif(opt.Verbose, 'Model has been validated.\n')
    % Check dependencies
    dispif(opt.Verbose, 'Checking state functions and dependencies...\n')
    model.checkStateFunctionDependencies();
    dispif(opt.Verbose, 'All checks ok. Model ready for simulation.\n')
    % Validate schedule
    dispif(opt.Verbose, 'Preparing schedule for simulation...\n')
    schedule = model.validateSchedule(schedule);
    dispif(opt.Verbose, 'All steps ok. Schedule ready for simulation.\n')

    % Check if initial state is reasonable
    dispif(opt.Verbose, 'Validating initial state...\n')
    state = model.validateState(initstate);
    dispif(opt.Verbose, 'Initial state ok. Ready to begin simulation.\n')
    
    %% Run ode15i
    solver = OdeWrapper(model,state,forces, schedule);
    [res,ode_state]=solver.solve();
end