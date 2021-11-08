classdef BareBattery_ < CompositeModel

    methods

        function model = BareBattery_()

            model = model@CompositeModel('battery');
            
            names = {'SOC', ...
                     'T', ...
                     'controlEq'};
            
            model.names = names;
            
            % setup the submodels
            submodels = {};
            % electrolyte
            submodels{end + 1} = Electrolyte_('elyte');
            % negative electrode
            ne_model = ElectrodeActiveComponent_('ne');
            ne_model.names{end + 1} = 'jExternal';
            submodels{end + 1} = ne_model;
            % positive electrode            
            pe_model = ElectrodeActiveComponent_('pe');
            pe_model.names{end + 1} = 'E';
            pe_model.names{end + 1} = 'I';
            pe_model.names{end + 1} = 'jExternal';
            submodels{end + 1} = pe_model;
            
            model.SubModels = submodels;
            
            %% update temperatures (dispatching)
            fn = @Battery.updateTemperature;
            
            fnmodel = {'..'};
            inputnames = {VarName({'..'}, 'T')};
            model = model.addPropFunction({'ne', 'T'}, fn, inputnames, fnmodel);
            model = model.addPropFunction({'pe', 'T'}, fn, inputnames, fnmodel);
            model = model.addPropFunction({'elyte', 'T'}, fn, inputnames, fnmodel);
           
                  
            %% setup couplings
            
            fn = @Battery.updateElectrodeCoupling;
            
            clear inputnames;
            inputnames{1} = VarName({'elyte'}, 'chargeCarrier');
            inputnames{1}.isNamingRelative = false;
            inputnames{2} = VarName({'elyte'}, 'phi');
            inputnames{2}.isNamingRelative = false;
            
            fnmodel = {'..', '..'};
            model = model.addPropFunction({'ne', 'am', 'phiElectrolyte'}, fn, inputnames, fnmodel);
            model = model.addPropFunction({'ne', 'am', 'chargeCarrierElectrolyte'}, fn, inputnames, fnmodel);
            model = model.addPropFunction({'pe', 'am', 'phiElectrolyte'}, fn, inputnames, fnmodel);
            model = model.addPropFunction({'pe', 'am', 'chargeCarrierElectrolyte'}, fn, inputnames, fnmodel);
            
            fn = @Battery.updateElectrolyteCoupling;
            
            clear inputnames;
            inputnames{1} = VarName({'ne', 'am'}, 'R');
            inputnames{1}.isNamingRelative = false;
            inputnames{2} = VarName({'pe', 'am'}, 'R');
            inputnames{2}.isNamingRelative = false;
            
            fnmodel = {'..'};
            model = model.addPropFunction({'elyte', 'chargeCarrierSource'}, fn, inputnames, fnmodel);
            model = model.addPropFunction({'elyte', 'eSource'}, fn, inputnames, fnmodel);
            
            
            fn = @Battery.setupExternalCouplingNegativeElectrode;
            inputnames = {'phi'};
            fnmodel = {'..'};
            model = model.addPropFunction({'ne', 'jBcSource'}, fn, inputnames, fnmodel);
            
            fn = @Battery.setupExternalCouplingPositiveElectrode;
            inputnames = {'phi', 'E'};
            fnmodel = {'.'};
            model = model.addPropFunction({'pe', 'jBcSource'}, fn, inputnames, fnmodel);
            
            %% setup control equation
            fn = @Batter.setupEIEquation;
            fnmodel = {'.'};
            inputnames = {{'pe', 'E'}, ...
                          {'pe', 'I'}, ...
                          {'pe', 'phi'}, ...
                         };
            model = model.addPropFunction({'controlEq'}, fn, inputnames, fnmodel);

                                                    
            %% setup external coupling at positive and negative electrodes
            
            fn = @Battery.setupExternalCouplingNegativeElectrode;
            inputnames = {'phi'};
            fnmodel = {'..'};
                      
            model = model.addPropFunction({'ne', 'jExternal'}, fn, inputnames, fnmodel);
            
            fn = @Battery.setupExternalCouplingPositiveElectrode;
            inputnames = {'phi', 'E'};
            fnmodel = {'.'};
            model = model.addPropFunction({'pe', 'jExternal'}, fn, inputnames, fnmodel);
            
            model = model.initiateCompositeModel();
            
        end
        
    end
    
end