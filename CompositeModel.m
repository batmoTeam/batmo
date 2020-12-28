classdef CompositeModel < SimpleModel

    properties
        SubModels;
        SubModelNames;
        nSubModels;
        
        isCompositeModel;
    end

    methods
        
        function model = CompositeModel(name, varargin)
        % The constructor function should be complemented so that the properties
        % SubModels, SubModelNames are defined and 
        % the function initiateCompositeModel must be called AT THE END.
            model = model@SimpleModel(name, varargin{:});
            model.hasparent = false;
        end
        
        function ind = getAssocModelInd(model, name)
            ind = strcmp(name, model.SubModelNames);
            if all(ind == 0)
                error('submodel not found');
            end
            ind = find(ind);
            if numel(ind) > 1
                error('submodels have same name');
            end
        end
        
        function submodel = getAssocModel(model, name)
            if isa(name, 'char') & ~any(strcmp(name, {'..', '.'}))
                ind = model.getAssocModelInd(name);
                submodel = model.SubModels{ind};
            else
                submodel = getAssocModel@SimpleModel(model, name);
            end
        end

        function model = setSubModel(model, name, submodel)
            ind = getAssocModelInd(model, name);
            model.SubModels{ind} = submodel;
        end
        
        
        function model = initiateCompositeModel(model)
            
            nsubmodels = numel(model.SubModels);
            model.nSubModels = nsubmodels;
            model.isCompositeModel = true;
            
            if ~model.hasparent
                model.namespace = {};
            end
            
            % Setup the namespaces and names for all the submodels
            for ind = 1 : nsubmodels
                submodel = model.SubModels{ind};
                submodel.hasparent = true; 
                submodel.parentmodel = model;
                
                submodel.namespace = horzcat(model.namespace, {submodel.getModelName()});
                
                if isa(submodel, 'CompositeModel')
                    submodel = submodel.initiateCompositeModel();
                end
                
                model.SubModels{ind} = submodel;
                model.SubModelNames{ind} = submodel.getModelName;
            end
            
        end
        
        function varnames = getModelPrimaryVarNames(model)
        
            varnames = model.assignCurrentNameSpace(model.pnames);
            nsubmodels = model.nSubModels;
            for i = 1 : nsubmodels
                submodel = model.SubModels{i};
                varnames1 = submodel.getModelPrimaryVarNames();
                varnames = horzcat(varnames, varnames1);
            end
            
        end
        
        function varnames = getModelVarNames(model)
        % default for compositemodel : fetch all the defined names in the submodels
        
            varnames = getModelVarNames@SimpleModel(model);
            nsubmodels = model.nSubModels;
            for i = 1 : nsubmodels
                submodel = model.SubModels{i};
                varnames1 = submodel.getModelVarNames();
                varnames = horzcat(varnames, varnames1);
            end
            
        end
        
        
        function [state, report] = updateState(model, state, problem, dx, drivingForces)
            waring('to be updated');
            % Due to current use of function updateState, we need to
            % reinitiate the primary variable (this is unfortunate).
            model = model.setPrimaryVarNames();
            nsubmodels = model.nSubModels;
            for i = 1 : nsubmodels
                submodel   = model.SubModels{i};
                [state, ~] = submodel.updateState(state, problem, dx, []);
            end
            report = [];
        end

        
        function [state, report] = updateAfterConvergence(model, state0, state, dt, drivingForces)
            waring('to be updated');
            nsubmodels = model.nSubModels;
            for i = 1 : nsubmodels
                submodel = model.SubModels{i};
                [state, ~] = submodel.updateAfterConvergence(state0, state, ...
                                                             dt, ...
                                                             drivingForces);
            end
            report = [];
        end
        
        function [val, state] = getUpdatedProp(model, state, name)
            if isa(name, 'VarName')
                namespace = name.namespace;
                name = name.name;
                submodel = model.getAssocModel(namespace);
                [val, state] = submodel.getUpdatedProp(state, name);
            elseif iscell(name)
                % syntaxic sugar (do not need to setup VarName)
                varname = VarName(name{1 : end - 1}, name{end});
                [val, state] = model.getUpdatedProp(state, varname);
            elseif ischar(name)
                [val, state] = getUpdatedProp@SimpleModel(model, state, name);
            else
                error('type of name is not recognized')
            end
        end
        
    end
    
end
