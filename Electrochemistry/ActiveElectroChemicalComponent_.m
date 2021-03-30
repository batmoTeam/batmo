classdef ActiveElectroChemicalComponent_ < ElectroChemicalComponent_

    methods

        function model = ActiveElectroChemicalComponent_(name)

            model = model@ElectroChemicalComponent_(name);
            
            model.SubModels{1} = ActiveMaterial_('am');
            
            fn = @ActiveElectroChemicalComponent.updateIonAndCurrentSource;
            inputnames = {VarName({'am'}, 'R')};
            fnmodel = {'.'};
            model = model.addPropFunction('chargeCarrierSource', fn, inputnames, fnmodel);
            model = model.addPropFunction('eSource', fn, inputnames, fnmodel);
            
            fn = @ActiveElectroChemicalComponent.updateChargeCarrier;
            inputnames = {VarName({'am'}, 'cs')};
            fnmodel = {'.'};
            model = model.addPropFunction('cs', fn, inputnames, fnmodel);

            fn = @ActiveElectroChemicalComponent.updatePhi;
            inputnames = {VarName({'am'}, 'phi')};
            fnmodel = {'.'};
            model = model.addPropFunction('phi', fn, inputnames, fnmodel);
            
            fn = @ActiveElectroChemicalComponent.updateT;
            inputnames = {VarName({'..'}, 'T')};
            fnmodel = {'..'};
            model = model.addPropFunction({'am', 'T'}, fn, inputnames, fnmodel);
            
        end
        
    end
    
end

