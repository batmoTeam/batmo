classdef ProtonicMembraneElectrolyte < BaseModel

    properties

        % Temperature
        T
        % Structure with physical constants
        constants
        % Equibrium p-type conductivity
        sigma_p0
        % Equibrium n-type conductivity
        sigma_n0
        % proton conductivity
        sigma_prot

        E_0_ref % used in computation of the electronic conductivity
        

        % Setup variables
        dS_hyd     
        dH_hyd     
        Y          
        Am         
        dH_ox      
        E_0        
        steam_ratio
        Ptot       
        SU
        Ea_prot
        
    end

    methods

        function model = ProtonicMembraneElectrolyte(paramobj)

            model = model@BaseModel();

            fdnames = {'G'          , ...
                       'T'          , ...
                       'sigma_n0'   , ...
                       'dS_hyd'     , ...
                       'dH_hyd'     , ...
                       'Y'          , ...
                       'Am'         , ...
                       'dH_ox'      , ...
                       'E_0'        , ...
                       'steam_ratio', ...
                       'Ptot'       , ...
                       'SU'         , ...
                       'Ea_prot'};

            model = dispatchParams(model, paramobj, fdnames);

            model.operators = localSetupOperators(model.G);

            model.constants = PhysicalConstants();

            c = model.constants;

            % Compute sigma_p0
            
            Y = model.Y;
            T = model.T;
            
            K_hyd              = exp((model.dS_hyd/c.R) - model.dH_hyd*1000/(T*c.R));
            K_H_p              = K_hyd; 
            p_ref              = ((3*K_H_p - sqrt(K_H_p*(9*K_H_p - 6*K_H_p*Y + K_H_p*Y^2 + 24*Y - 4*Y^2)))/(K_H_p - 4));
            sigma_p_masoud_std = c.F*(1/T)*(3*(Y - p_ref)/2)^(1/2)*(3)^(- 1/2)*1^(1/4)*model.Am*exp(-model.dH_ox/(c.R.*T));
            sigma_p0           = sigma_p_masoud_std;
            
            % Compute E_0_ref

            E_0_ref = model.E_0 - 0.00024516.*T - c.R.*T./(2*c.F)*log(1./(1^(1/2)));

            % Compute sigma_prot

            pH2O_in = model.steam_ratio*model.Ptot;
            pH2O = pH2O_in*(1 - model.SU);
            
            pH2O_neg = 0.05*model.Ptot;
            
            K_H     = K_hyd*pH2O; 
            K_H_neg = K_hyd*pH2O_neg;
    
            OH_pos  = ((3*K_H - sqrt(K_H*(9*K_H - 6*K_H*Y + K_H*Y^2 + 24*Y - 4*Y^2)))/(K_H - 4)); 
            OH_neg = ((3*K_H_neg - sqrt(K_H_neg*(9*K_H_neg - 6*K_H_neg*Y + K_H_neg*Y^2 + 24*Y - 4*Y^2)))/(K_H_neg - 4)); 

            D0_prot = 0.021*38.1/T; % pre - exp proton diffusion
            D_prot  = D0_prot*exp(-(model.Ea_prot*1000)/(c.R*T)); 
            
            sigma_prot_pos = (c.F*OH_pos*D_prot);
            sigma_prot_neg = (c.F*OH_neg*D_prot);
                
            sigma_prot = (sigma_prot_pos + sigma_prot_neg)/2; 

            % Assign values
            
            model.sigma_p0   = sigma_p0*(1/(centi*meter));
            model.sigma_n0   = model.sigma_n0*(1/(centi*meter)); % we convert to SI : from Siemens/centimeter to Siemens/meter
            model.sigma_prot = sigma_prot*(1/(centi*meter));

            model.E_0_ref    = E_0_ref;
            
        end

        function model = registerVarAndPropfuncNames(model)

            model = registerVarAndPropfuncNames@BaseModel(model);

            varnames = {};

            % Electrostatic potential phi
            varnames{end + 1} = 'phi';
            % Electromotive potential pi (see Jacobsen and Mogensen paper) also called Electrochemical potential
            varnames{end + 1} = 'pi';
            % Electronic Chemical potential E
            varnames{end + 1} = 'E';
            % Electronic conductivity
            varnames{end + 1} = 'sigmaEl';
            % Hp conductivity
            varnames{end + 1} = 'sigmaHp';
            % H+ source term
            varnames{end + 1} = 'sourceHp';
            % Electronic source term
            varnames{end + 1} = 'sourceEl';
            % H+ flux
            varnames{end + 1} = 'jHp';
            % Electronic flux
            varnames{end + 1} = 'jEl';
            % H+ mass conservation (we measure the mass in Coulomb, hence "massConsHp")
            varnames{end + 1} = 'massConsHp';
            % Charge conservation
            varnames{end + 1} = 'chargeConsEl';
            % Charge conservation
            varnames{end + 1} = 'alpha';

            model = model.registerVarNames(varnames);

            fn = @ProtonicMembraneElectrolyte.updateE;
            inputnames = {'phi', 'pi'};
            model = model.registerPropFunction({'E', fn, inputnames});

            fn = @ProtonicMembraneElectrolyte.updateSigmaHp;
            inputnames = {};
            model = model.registerPropFunction({'sigmaHp', fn, inputnames});

            fn = @ProtonicMembraneElectrolyte.updateHpFlux;
            inputnames = {'phi'};
            model = model.registerPropFunction({'jHp', fn, inputnames});

            fn = @ProtonicMembraneElectrolyte.updateElConductivity;
            inputnames = {'E', 'alpha'};
            model = model.registerPropFunction({'sigmaEl', fn, inputnames});

            fn = @ProtonicMembraneElectrolyte.updateElFlux;
            inputnames = {'sigmaEl', 'pi'};
            model = model.registerPropFunction({'jEl', fn, inputnames});

            fn = @ProtonicMembraneElectrolyte.updateMassConsHp;
            inputnames = {'sourceHp', 'jHp'};
            model = model.registerPropFunction({'massConsHp', fn, inputnames});

            fn = @ProtonicMembraneElectrolyte.updateChargeConsEl;
            inputnames = {'sourceEl', 'jEl'};
            model = model.registerPropFunction({'chargeConsEl', fn, inputnames});

        end

        function state = updateE(model, state)

            state.E = state.pi - state.phi;

        end

        function state = updateSigmaHp(model, state)

            nc = model.G.cells.num;

            state.sigmaHp = model.sigma_prot*ones(nc, 1);

        end

        function state = updateHpFlux(model, state)

            op = model.operators;

            sigmaHp = state.sigmaHp;
            phi     = state.phi;

            state.jHp = assembleFlux(model, phi, sigmaHp);

        end

        function state = updateElConductivity(model, state)

            F = model.constants.F;
            R = model.constants.R;
            T = model.T;

            sigma_p0 = model.sigma_p0;
            sigma_n0 = model.sigma_n0;
            E_0_ref  = model.E_0_ref;

            E     = state.E;
            alpha = state.alpha;

            f = F/(R*T);
            % Extra smoothing locally around alpha = 0
            alpha = 1 - cos(pi/2*alpha);

            regularisationCase = 'exponential coefficient';

            switch regularisationCase

              case 'linear'

                sigmaEl = (1 - alpha)*(sigma_p0 + sigma_n0) + alpha*sigmaEl;

              case 'exponential coefficient'

                f = f*alpha;
                sigmaEl = sigma_p0*exp(f*(E - E_0_ref)) + sigma_n0*exp(-f*E);

              otherwise

                error('regularisationCase not recognized');

            end

            doCutOff = false;

            if doCutOff

                sigmaElMin = 1e-6;
                ind = value(sigmaEl) < sigmaElMin;
                sigmaEl(ind) = sigmaElMin;

            end

            state.sigmaEl = sigmaEl;

        end

        function state = updateElFlux(model, state)

            sigmaEl = state.sigmaEl;
            pi      = state.pi;

            state.jEl = assembleFlux(model, pi, sigmaEl);

        end


        function state = updateChargeConsEl(model, state)

            op = model.operators;

            sourceEl = state.sourceEl;
            jEl      = state.jEl;

            state.chargeConsEl =  op.Div(jEl) - sourceEl;

        end

        function state = updateMassConsHp(model, state)

            op = model.operators;

            sourceHp = state.sourceHp;
            jHp      = state.jHp;

            state.massConsHp =  op.Div(jHp) - sourceHp;

        end

    end

end
