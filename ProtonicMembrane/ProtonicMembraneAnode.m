classdef ProtonicMembraneAnode < ProtonicMembraneElectrode
    
    properties
        
        % coefficient in Buttler-Volmer
        beta
        
        % charge-transfer current density
        i_0

        % Limiting current densities
        ila % Anode
        ilc % Cathode

        n
        
        R_ct_0
        Ea_ct      
        SU         
        O2_conc_feed
        steam_ratio
        Ptot
        
    end
    
    methods
        
        function model = ProtonicMembraneAnode(paramobj)

            model = model@ProtonicMembraneElectrode(paramobj);

            fdnames = {'beta'        , ...
                       'ila'         , ...
                       'ilc'         , ...
                       'R_ct_0'      , ...
                       'Ea_ct'       , ...
                       'n'           , ...
                       'SU'          , ...
                       'O2_conc_feed', ...
                       'steam_ratio' , ...
                       'Ptot'};
            
            model = dispatchParams(model, paramobj, fdnames);
            
            model.constants = PhysicalConstants();

            c = model.constants;

            T = model.T;
            
            % compute pressures to setup Eocv
            
            pO2_in  = model.O2_conc_feed*(1 - model.steam_ratio)*model.Ptot;
            pH2O_in = model.steam_ratio*model.Ptot;

            pO2  = pO2_in + model.SU*pH2O_in/2;
            pH2O = pH2O_in*(1 - model.SU);

            Eocv = model.E_0 - 0.00024516.*T - c.R.*T./(2*c.F)*log(pH2O./(pO2^(1/2))); 
            
            % Compute charge-transfer current density
            
            R_ct = model.R_ct_0.*exp(model.Ea_ct./(c.R.*T)).*pO2.^(-0.2); 
            f = c.F/(c.R*T);
            i_0 = 1./(R_ct.*f.*model.n); % charge-transfer current density

            % Assign the computed values
            
            model.i_0   = i_0;
            model.Eocv = Eocv;
            
            
        end
        
        function model = registerVarAndPropfuncNames(model)
        
            model = registerVarAndPropfuncNames@ProtonicMembraneElectrode(model);

            fn = @ProtonicMembraneAnode.updateJHp;
            inputnames = {'eta'};
            model = model.registerPropFunction({'jHp', fn, inputnames});
            
            % fn = @ProtonicMembraneAnode.updateEta2;
            % inputnames = {'j', 'alpha'};
            % model = model.registerPropFunction({'eta', fn, inputnames});

            % fn = @ProtonicMembraneAnode.updatePhi2;
            % inputnames = {'eta', 'pi', 'Eocv'};
            % model = model.registerPropFunction({'phi', fn, inputnames});


        end
        
        
        function state = updateJHp(model, state)
            
            con  = model.constants;

            beta = model.beta;
            ila  = model.ila;
            ilc  = model.ilc;
            i0   = model.i_0;
            
            eta   = state.eta;
            
            feta = con.F*model.n/(con.R*model.T).*eta;
            
            jHp = -i0*(exp(-beta*feta) - exp((1 - beta)*feta))./(1 + (i0/ilc)*exp(-beta*feta) - (i0/ila)*exp((1 - beta)*feta));

            % jHp = i0*(exp(feta/2) - exp(-feta/2))/2;
            
            % R = 5;
            % jHp = 1/R*eta;
            
            state.jHp = jHp;
            
        end

        % function state = updateEta2(model, state)

        %     R = 0.05;
            
        %     j = state.j;
        %     eta = R*j; 
            
        %     state.eta = eta;
            
        % end

        % function state = updatePhi2(model, state)

        %     state.phi = state.pi - state.eta - state.Eocv;
            
        % end

        
    end
    
end

