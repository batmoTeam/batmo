classdef ActiveElectroChemicalComponent < ElectroChemicalComponent
    
    properties
        ActiveMaterial
        
        volumeFraction
        porosity
        thickness
        
    end
    
    methods
        
        function model = ActiveElectroChemicalComponent(paramobj)
        % shortcut used here:
        % am = ActiveMaterial
            
            model = model@ElectroChemicalComponent(paramobj);
            
            % Setup ActiveMaterial component
            paramobj.am.G = model.G;
            am = ActiveMaterial(paramobj.am);
            model.ActiveMaterial = am;

            % setup volumeFraction, porosity, thickness
            nc = model.G.cells.num;
            volumeFraction = am.volumeFraction*ones(nc, 1);
            model.volumeFraction = volumeFraction;
            model.porosity = 1 - model.volumeFraction;
            model.thickness = 10e-6;
            
            % setup effective electronic conductivity
            econd = am.electronicConductivity;
            model.EffectiveElectronicConductivity = econd .* volumeFraction.^1.5;
            
            
        end

        function state = updateIonAndCurrentSource(model, state)
            
            ccSourceName = model.chargeCarrierSourceName;
            
            R = state.ActiveMaterial.R;
            
            state.eSource = R;
            state.(ionSourceName) = -R;
            
        end
        
        function state = updateChargeCarrier(model, state)
            state.(ionName) = state.ActiveMaterial.(ionName);
        end 
        
        function state = updatePhi(model, state)
            state.phi = state.ActiveMaterial.phi;
        end         
        
        function state = updateT(model, state)
            state.ActiveMaterial.T = state.T;
        end
        
        
    end
end

