classdef Coating < ElectronicComponent

    properties

        %% Sub-Models

        ActiveMaterial
        Binder
        ConductingAdditive

        % The two following models are instantiated only when active_material_type == 'composite' and, in this case,
        % ActiveMaterial model will remain empty. If active_material_type == 'default', then the two models remains empty
        ActiveMaterial1
        ActiveMaterial2

        %% Input Parameters

        % Standard parameters
        effectiveDensity     % the mass density of the material (symbol: rho). Important : the density is computed with respect to total volume (including the empty pores)
        bruggemanCoefficient % the Bruggeman coefficient for effective transport in porous media (symbol: beta)
        active_material_type % 'default' (only one particle type) or 'composite' (two different particles)

        % Advanced parameters (used if given, otherwise computed)
        volumeFractions                 % mass fractions of each components (if not given computed subcomponent and density)
        volumeFraction
        thermalConductivity             % (if not given computed from the subcomponents)
        specificHeatCapacity            % (if not given computed from the subcomponents)
        effectiveThermalConductivity    % (account for volume fraction, if not given, computed from thermalConductivity)
        effectiveVolumetricHeatCapacity % (account for volume fraction and density, if not given, computed from specificHeatCapacity)

        % external coupling parameters
        externalCouplingTerm % structure to describe external coupling (used in absence of current collector)

        %% Computed parameters at model setup
        compInds            % index of the sub models in the massFractions structure

    end

    methods

        function model = Coating(paramobj)

            model = model@ElectronicComponent(paramobj);

            fdnames = {'effectiveDensity'               , ...
                       'bruggemanCoefficient'           , ...
                       'active_material_type'           , ...
                       'volumeFractions'                , ...
                       'volumeFraction'                 , ...
                       'thermalConductivity'            , ...
                       'specificHeatCapacity'           , ...
                       'effectiveThermalConductivity'   , ...
                       'effectiveVolumetricHeatCapacity', ...
                       'externalCouplingTerm'};

            model = dispatchParams(model, paramobj, fdnames);

            sd = 'SolidDiffusion';
            am = 'ActiveMaterial';
            bd = 'Binder';
            ad = 'ConductingAdditive';

            switch model.active_material_type
              case 'default'
                am = 'ActiveMaterial';
                compnames = {am, bd, ad};
              case 'composite'
                am1 = 'ActiveMaterial1';
                am2 = 'ActiveMaterial2';
                compnames = {am1, am2, bd, ad};
              otherwise
                error('active_material_type not recognized.');
            end

            model.subModelNameList = compnames;


            %% We setup the volume fractions of each components

            % Compute the specific volumes of each component based on the density and mass fraction
            % If components or values are missing, the volume fraction is set to zero
            specificVolumes = zeros(numel(compnames), 1);
            for icomp = 1 : numel(compnames)
                compname = compnames{icomp};
                compInds.(compname) = icomp;
                if ~isempty(paramobj.(compname))
                    rho = paramobj.(compname).density;
                    mf  = paramobj.(compname).massFraction;
                    if ~isempty(rho) & ~isempty(mf)
                        specificVolumes(icomp) = mf/rho;
                    end
                end
            end

            model.compInds = compInds;

            % We treat special cases

            switch model.active_material_type
              case 'default'
                if all(specificVolumes == 0)
                    % No data has been given, we assume that there is no binder and conducting additive
                    model.volumeFractions = zeros(numel(compnames), 1);
                    model.volumeFractions(compInds.(am)) = 1;
                    model.(am).massFraction = 1;
                else
                    if specificVolumes(compInds.(am)) == 0
                        error('missing density and/or massFraction for the active material. The volume fraction cannot be computed ');
                    end
                end
              case 'composite'
                if all(specificVolumes([compInds.(am1), compInds.(am2)]) == 0)
                    assert(~isempty(model.volumeFractions) && ~isempty(model.volumeFraction), ...
                           'Data in the subcomponents are missing. You can also provide volumeFractions and volumeFraction directly' )
                end
              otherwise
                error('active material type not recognized');
            end

            % We normalize the volume fractions

            if isempty(model.volumeFractions)

                volumeFractions = zeros(numel(compnames), 1);
                sumSpecificVolumes = sum(specificVolumes);
                for icomp = 1 : numel(compnames)
                    volumeFractions(icomp) = specificVolumes(icomp)/sumSpecificVolumes;
                end

                model.volumeFractions = volumeFractions;

            end

            %% We setup the volume fraction of coating

            if isempty(model.volumeFraction)

                % If the volumeFraction is given, we use it otherwise it is computed from the density and the specific
                % volumes of the components
                assert(~isempty(model.effectiveDensity), 'At this point we need an effective density in the model');
                model.volumeFraction = sumSpecificVolumes*model.effectiveDensity;

            end

            %% We setup the electronic conductivity

            if isempty(model.electronicConductivity)
                % if electronic conductivity is given, we use it otherwise we compute it as a volume average of the component
                kappa = 0;
                for icomp = 1 : numel(compnames)
                    compname = compnames{icomp};
                    if ~isempty(paramobj.(compname)) && ~isempty(paramobj.(compname).electronicConductivity)
                        kappa = kappa + model.volumeFractions(icomp)*paramobj.(compname).electronicConductivity;
                    end
                end
                assert(abs(kappa) > 0, 'The electronicConductivity must be provided for at least one component');
                model.electronicConductivity = kappa;
            end

            if isempty(model.effectiveElectronicConductivity)

                kappa = model.electronicConductivity;
                vf    = model.volumeFraction;
                bg    = model.bruggemanCoefficient;

                model.effectiveElectronicConductivity = kappa*vf^bg;

            end

            %% We setup the thermal parameters

            if model.use_thermal

                %% We setup the thermal conductivities

                if isempty(model.thermalConductivity)
                    bg = model.bruggemanCoefficient;
                    thermalConductivity = 0;
                    for icomp = 1 : numel(compnames)
                        compname = compnames{icomp};
                        thermalConductivity = thermalConductivity + (model.volumeFractions(icomp))^bg*paramobj.(compname).thermalConductivity;
                    end
                    model.thermalConductivity = thermalConductivity;
                end

                if isempty(model.effectiveThermalConductivity)
                    bg = model.bruggemanCoefficient;
                    model.effectiveThermalConductivity = (model.volumeFraction).^bg.*model.thermalConductivity;
                end

                %% We setup the thermal capacities

                if isempty(model.specificHeatCapacity)
                    specificHeatCapacity = 0;
                    for icomp = 1 : numel(compnames)
                        compname = compnames{icomp};
                        specificHeatCapacity = specificHeatCapacity + model.(compname).massFraction*paramobj.(compname).specificHeatCapacity;
                    end
                    model.specificHeatCapacity = specificHeatCapacity;
                end

                if isempty(model.effectiveVolumetricHeatCapacity)
                    model.effectiveVolumetricHeatCapacity = model.volumeFraction*model.effectiveDensity*model.specificHeatCapacity;
                end

            end

            %% Setup the submodels

            np = paramobj.G.cells.num;
            switch paramobj.active_material_type
              case 'default'
                paramobj.(am).(sd).volumeFraction = model.volumeFraction*model.volumeFractions(model.compInds.(am));
                if strcmp(paramobj.(am).diffusionModelType, 'full')
                    paramobj.(am).(sd).np = np;
                end
                model.ActiveMaterial = ActiveMaterial(paramobj.ActiveMaterial);
              case 'composite'
                ams = {am1, am2};
                for iam = 1 : numel(ams)
                    amc = ams{iam};
                    paramobj.(amc).(sd).volumeFraction = model.volumeFraction*model.volumeFractions(model.compInds.(amc));
                    if strcmp(paramobj.(amc).diffusionModelType, 'full')
                        paramobj.(amc).(sd).np = np;
                    end
                    model.(amc) = ActiveMaterial(paramobj.(amc));
                end
              otherwise
                error('active_material_type not recognized');
            end

            model.Binder             = Binder(paramobj.Binder);
            model.ConductingAdditive = ConductingAdditive(paramobj.ConductingAdditive);

        end

        function model = registerVarAndPropfuncNames(model)

            %% Declaration of the Dynamical Variables and Function of the model
            % (setup of varnameList and propertyFunctionList)

            model = registerVarAndPropfuncNames@ElectronicComponent(model);

            itf = 'Interface';
            sd  = 'SolidDiffusion';

            varnames = {'jCoupling', ...
                        'jExternal', ...
                        'SOC'};

            model = model.registerVarNames(varnames);

            % We declare SOC as an extra variable, as it is not used in assembly (otherwise it will be systematically
            % computed but not used)
            model = model.setAsExtraVarName('SOC');

            switch model.active_material_type

              case 'default'

                am = 'ActiveMaterial';

                fn = @Coating.updateEsource;
                model = model.registerPropFunction({'eSource', fn, {{am, sd, 'Rvol'}}});

                fn = @Coating.updatePhi;
                model = model.registerPropFunction({{am, itf, 'phiElectrode'}, fn, {'phi'}});

                fn = @Coating.dispatchTemperature;
                model = model.registerPropFunction({{am, 'T'}, fn, {'T'}});

                fn = @Coating.updateSOC;
                model = model.registerPropFunction({'SOC', fn, {{am, sd, 'cAverage'}}});

              case 'composite'

                am1 = 'ActiveMaterial1';
                am2 = 'ActiveMaterial2';

                varnames = {{am1, 'SOC'}, ...
                            {am2, 'SOC'}};

                model = model.registerVarNames(varnames);
                model = model.setAsExtraVarNames(varnames);

                % We remove the dUdT variable (not used for non thermal simulation)
                varnames = {{am1, itf, 'dUdT'}, ...
                            {am2, itf, 'dUdT'}};

                model = model.removeVarNames(varnames);

                fn = @Coating.updateCompositeEsource;
                inputnames = {{am1, sd, 'Rvol'}, ...
                              {am2, sd, 'Rvol'}};
                model = model.registerPropFunction({'eSource', fn, inputnames});

                fn = @Coating.updateCompositePhi;
                model = model.registerPropFunction({{am1, itf, 'phiElectrode'}, fn, {'phi'}});
                model = model.registerPropFunction({{am2, itf, 'phiElectrode'}, fn, {'phi'}});

                fn = @Coating.dispatchCompositeTemperature;
                model = model.registerPropFunction({{am1, 'T'}, fn, {'T'}});
                model = model.registerPropFunction({{am2, 'T'}, fn, {'T'}});

                fn = @Coating.updateCompositeSOC;
                inputnames = {{am1, sd, 'cAverage'}, ...
                              {am2, sd, 'cAverage'}};
                model = model.registerPropFunction({'SOC', fn, inputnames});
                model = model.registerPropFunction({{am1, 'SOC'}, fn, inputnames});
                model = model.registerPropFunction({{am2, 'SOC'}, fn, inputnames});

              otherwise

                error('active material type not recognized.')

            end

            if model.use_thermal
                varnames = {'jFaceCoupling', ...
                            'jFaceExternal'};
                model = model.registerVarNames(varnames);

            end

            fn = @Coating.updatejBcSource;
            model = model.registerPropFunction({'jBcSource', fn, {'jCoupling', 'jExternal'}});

            if model.use_thermal
                fn = @Coating.updatejFaceBc;
                model = model.registerPropFunction({'jFaceBc', fn, {'jFaceCoupling', 'jFaceExternal'}});
            end

            fn = @Coating.updatejExternal;
            model = model.registerPropFunction({'jExternal', fn, {}});
            if model.use_thermal
                model = model.registerPropFunction({'jFaceExternal', fn, {}});
            end

            fn = @Coating.updatejCoupling;
            model = model.registerPropFunction({'jCoupling', fn, {}});
            if model.use_thermal
                model = model.registerPropFunction({'jFaceCoupling', fn, {}});
            end

        end


        function state = updatejBcSource(model, state)

            state.jBcSource = state.jCoupling + state.jExternal;

        end

        function state = updatejFaceBc(model, state)

            state.jFaceBc = state.jFaceCoupling + state.jFaceExternal;

        end

        function state = updatejExternal(model, state)

            state.jExternal     = 0;
            state.jFaceExternal = 0;

        end

        function state = updatejCoupling(model, state)

            state.jCoupling     = 0;
            state.jFaceCoupling = 0;

        end

        function state = updateEsource(model, state)

            am  = 'ActiveMaterial';
            sd  = 'SolidDiffusion';
            itf = 'Interface';

            F    = model.constants.F;
            n    = model.(am).(itf).numberOfElectronsTransferred;
            vols = model.G.cells.volumes;

            state.eSource =  - n*F*vols.*state.(am).(sd).Rvol;

        end

       function state = updateCompositeEsource(model, state)

            am1 = 'ActiveMaterial1';
            am2 = 'ActiveMaterial2';
            itf = 'Interface';
            sd  = 'SolidDiffusion';

            F    = model.constants.F;
            vols = model.G.cells.volumes;

            ams = {am1, am2};

            Rvol = 0;

            for iam = 1 : numel(ams)

                amc = ams{iam};

                n    = model.(amc).(itf).numberOfElectronsTransferred;
                Rvol = Rvol + n*F*state.(amc).(sd).Rvol;

            end

            state.eSource = - vols.*Rvol;

        end


        function state = updateCompositePhi(model, state)

            am1 = 'ActiveMaterial1';
            am2 = 'ActiveMaterial2';
            itf = 'Interface';

            ams = {am1, am2};

            for iam = 1 : numel(ams)

                amc = ams{iam};
                state.(amc).(itf).phiElectrode = state.phi;

            end

        end

        function state = updatePhi(model, state)

            am  = 'ActiveMaterial';
            itf = 'Interface';

            state.(am).(itf).phiElectrode = state.phi;

        end

        function state = dispatchCompositeTemperature(model, state)

            am1 = 'ActiveMaterial1';
            am2 = 'ActiveMaterial2';

            ams = {am1, am2};

            for iam = 1 : numel(ams)

                amc = ams{iam};
                state.(amc).T = state.T;

            end

        end

        function state = dispatchTemperature(model, state)
            am  = 'ActiveMaterial';
            state.(am).T = state.T;
        end


        function state = updateSOC(model, state)

            % shortcut
            am  = 'ActiveMaterial';
            itf = 'Interface';
            sd  = 'SolidDiffusion';

            vf       = model.volumeFraction;
            am_frac  = model.volumeFractions(model.compInds.(am));
            vols     = model.G.cells.volumes;
            cmax     = model.(am).(itf).saturationConcentration;
            theta100 = model.(am).(itf).guestStoichiometry100;
            theta0   = model.(am).(itf).guestStoichiometry0;

            c = state.(am).(sd).cAverage;

            theta = c/cmax;
            m     = (1 ./ (theta100 - theta0));
            b     = -m .* theta0;
            SOC   = theta*m + b;
            vol   = am_frac*vf.*vols;

            SOC = sum(SOC.*vol)/sum(vol);

            state.SOC = SOC;

        end

        function state = updateCompositeSOC(model, state)

            am1 = 'ActiveMaterial1';
            am2 = 'ActiveMaterial2';
            itf = 'Interface';
            sd  = 'SolidDiffusion';

            vf    = model.volumeFraction;
            vols = model.G.cells.volumes;

            ams = {am1, am2};

            for iam = 1 : numel(ams)

                amc = ams{iam};

                am_frac  = model.volumeFractions(model.compInds.(amc));
                cmax     = model.(amc).(itf).saturationConcentration;
                theta100 = model.(amc).(itf).guestStoichiometry100;
                theta0   = model.(amc).(itf).guestStoichiometry0;

                c = state.(amc).(sd).cAverage;

                vol = am_frac*vf.*vols;

                molvals(iam)    = sum(c.*vol);
                molval0s(iam)   = theta0*cmax*sum(vol);
                molval100s(iam) = theta100*cmax*sum(vol);

                state.(amc).SOC = (molvals(iam) - molval0s(iam))/(molval100s(iam) - molval0s(iam));

            end

            molval    = sum(molvals);
            molval0   = sum(molval0s);
            molval100 = sum(molval100s);

            state.SOC = (molval - molval0)/(molval100 - molval0);

        end


    end
end
