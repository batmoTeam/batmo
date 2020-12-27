classdef SimpleModel < PhysicalModel
    
    properties
        parentmodel
        hasparent

        modelname
        
        % Own variables
        namespace
        
        names
        pnames
        
        aliases

        varfunctions
    end
    
    
    methods
        function model = SimpleModel(modelname, varargin)
            model = model@PhysicalModel([]);
            model = merge_options(model, varargin{:});
            model.modelname = modelname;
            % By default, the model has no parent so that the namespace is empty
            model.namespace = {};
            model.hasparent = false;
            % no variables listed by default
            model.names     = {};
            model.pnames    = {};
            model.aliases   = {};
        end

        function state = validateState(model, state)
            
            varnames = model.getModelVarNames();
            
            for i = 1 : numel(varnames)
                varname = varnames{i};
                name = varname.getfieldname;
                if ~isfield(state, name)
                    state.(name) = [];
                end
            end
            
        end
        
        function modelname = getModelName(model);
            modelname = model.modelname;
        end
        
        function parentmodel = getParentModel(model)
             parentmodel = model.parentmodel;
        end

        
        function varnames = getModelPrimaryVarNames(model)
        % List the primary variables. For SimpleModel the variable names only consist of those declared in the model (no child)
            varnames = model.assignCurrentNameSpace(model.pnames);
        end
        
        
        function varnames = getModelVarNames(model)
        % List the variable names (primary variables are handled separately). For SimpleModel the variable names only consist of
        % those declared in the model (no child)
            varnames = model.assignCurrentNameSpace(model.names);
            if model.hasparent
                return
            else
                % We add the alias if they belong to external quantities
                
                % First, we list them up and get unique instances
                varnames2 = cellfun(@(alias) alias{2}, model.aliases, 'uniformoutput', false);
                for ind = 1 : numel(varnames2)
                    fieldnames{ind} = varnames2{ind}.getfieldname;
                end
                [~, ind] = unique(fieldnames);
                varnames2 = varnames2(ind);
                
                % We remove the alias that are not external
                varnames3 = {};
                for ind = 1 : numel(varnames2)
                    if varnames2{ind}.isexternal()
                        varnames3{end + 1} = varnames2{ind};
                    end
                end
                varnames = horzcat(varnames, varnames3);
            end
        end

        function names = getFullVarNames(model)
        % Returns full names (i.e. including namespaces)
            varnames = model.getModelVarNames();
            names = {};
            for i = 1 : numel(varnames)
                names{end + 1} = varnames{i}.getfieldname;
            end
        end
        
        function names = getFullPrimaryVarNames(model)
        % Returns full names (i.e. including namespaces)
            varnames = model.getModelPrimaryVarNames();
            names = {};
            for i = 1 : numel(varnames)
                names{end + 1} = varnames{i}.getfieldname;
            end
        end
        
        function fullnames = addNameSpace(model, varnames)
        % Return a name (string) which identify uniquely the pair (namespace, name). This is handled here by adding "_" at the
        % end of the namespace and join it to the name.
            if iscell(names)
                for ind = 1 : numel(namespaces)
                    fullnames{ind} = model.addNameSpace(namespaces{ind}, names{ind});
                end
            else
                fullnames = varnames.join();
            end
        end
        
        function [isalias, varname] = setupVarName(model, name)
        % check if name is an alias
            aliases = model.aliases;
            isalias = false;
            varname = [];
            
            if isempty(aliases)
                return
            end
            
            for ind = 1 : numel(aliases)
                alias = aliases{ind};
                if strcmp(name, alias{1})
                    varname = alias{2};
                    isalias = true;
                    return
                end
            end
        end
            
        
        function [val, state] = getUpdatedProp(model, state, name)
            state = model.updateProp(state, name);
            val = model.getProp(state, name);
        end
        
        function state = updateProp(model, state, name)
            val = model.getProp(state, name);
            
            % check for vector variables
            isupdated = false;
            
            if ~isempty(val) 
                isupdated = true;
            end
            
            % Check for cell variables
            if iscell(val)
                isupdated = true;
                for ind = 1 : numel(val)
                    if isempty(val{ind})
                        isupdated = false;
                        break
                    end
                end
            end
            
            if isupdated
                return
            end
            
            
            % We look for an updating function for the variable
            [isalias, varname] = model.setupVarName(name);
            if isalias
                if isa(varname, 'LocalName')
                    name = varname.name;
                elseif model.hasparent
                    % Call alias
                    parentmodel = model.getParentModel();
                    state = parentmodel.updateProp(state, varname.name);
                    return
                else
                    error('this case is not handled');
                end
            end
            % find the updating property
            varfunctions = model.varfunctions;
            updatefn = [];
            for ind = 1 : numel(varfunctions)
                varfunction = varfunctions{ind};
                if strcmp(varfunction{1}, name)
                    updatefn = varfunction{2};
                    break
                end
            end
            state = updatefn(model, state);
            
        end
        
        function [fn, index] = getVariableField(model, name, throwError, varargin)
        % In this function the variable name is associated to a field name (fn) which corresponds to the field where the
        % variable is stored in the state.  See PhysicalModel
            
            opt = struct('index', []);
            opt = merge_options(opt, varargin{:});
            if isempty(opt.index)
                index = ':';
            else
                index = opt.index;
            end
            
            % Check if there exist an alias
            [isalias, varname] = model.setupVarName(name);
            
            if isalias && (varname.isexternal)
                isexternal = true;
            else
                isexternal = false;
            end
            
            if isalias & ~isexternal
                if isa(varname, 'LocalName')
                    [fn, index] = model.getVariableField(varname.name, true, 'index', varname.index);
                elseif model.hasparent
                    % Call alias
                    parentmodel = model.getParentModel();
                    [fn, index] = parentmodel.getVariableField(varname);
                else
                    error('this case is not handled');
                end
            else
                % Check that name is declared
                isok = ismember(name, model.names);
                % Otherwise it can be an alias refering to an external field 
                isok = isok | isexternal;
                assert(isok, 'name is not declared/recognized by the model');
                
                % Construct name from namespace
                namespace = model.namespace;
                varname = VarName(namespace, name);
                fn = varname.getfieldname();
                index = index;
            end
        end
        
        
        function varnames = assignCurrentNameSpace(model, names)
        % utility function which returns a cell consisting of the current model namespace with the same size as names.
            namespace = model.namespace;
            n = numel(names);
            varnames = {};
            for ind = 1 : n
                varnames{end + 1} = VarName(namespace, names{ind});
            end
        end
        
    end

end
