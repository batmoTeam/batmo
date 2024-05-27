function jsonstruct = equalizeJsonStructField(jsonstruct, fieldnamelist1, fieldnamelist2, varargin)

    value1 = getJsonStructField(jsonstruct, fieldnamelist1);
    value2 = getJsonStructField(jsonstruct, fieldnamelist2);

    if isUnAssigned(value1)

        if isUnAssigned(value2)

            return
            
        else
            
            jsonstruct = setJsonStructField(jsonstruct, fieldnamelist1, value2);

        end

    else

        if isUnAssigned(value2)
            
            jsonstruct = setJsonStructField(jsonstruct, fieldnamelist2, value1);

        else

            if isequal(value1, value2)

                return

            else

                opt = struct('force', 'false', ...
                             'warn', true);
                opt = merge_options(opt, varargin{:});

                if opt.force
                    jsonstruct = setJsonStructField(jsonstruct, fieldnamelist2, value1, 'handleMisMatch', 'quiet');
                    if opt.warn
                        fprintf('Fist value given in equalizeJsonStructField is taken\n');
                    end
                else
                    error('mismatch in equalizeJsonStructField');
                end
                
            end
        end

    end
      


    
end