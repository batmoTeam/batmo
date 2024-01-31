classdef FlatJsonViewer

    properties

        flatjson
        columnnames
        
    end

    methods

        function fjv  = FlatJsonViewer(flatjson, columnnames)

            fjv.flatjson = flatjson;

            if nargin < 2
                ncol = size(flatjson, 2);
                % default values for the column
                columnnames{1} = 'parameter name';
                if ncol == 2
                    columnnames{2} = 'parameter value';
                else
                    columnnames{2} = 'first set';
                    columnnames{3} = 'second set';
                    if ncol == 4
                        columnnames{4} = 'comparison';
                    end
                end
            end
            
            fjv.columnnames = columnnames;
            
        end


        function print(fjv, filterdesc)

            if nargin > 1
                fjv = fjv.filter(filterdesc);
            end
            
            cell2table(fjv.flatjson, 'VariableNames', fjv.columnnames)
            
        end

        function sortedfjv = sort(fjv, orderdesc)

            columnnames = fjv.columnnames;
            flatjson    = fjv.flatjson;

            ncol = numel(columnnames);

            if ischar(orderdesc)
                orderdesc = {orderdesc};
            end
            
            for iorder = numel(orderdesc) : -1 : 1

                r = regexprep(orderdesc{iorder}, ' +', '.*');
                ind = regexp(columnnames, r);
                ind = cellfun(@(res) ~isempty(res), ind);
                ind = find(ind);

                assert(numel(ind) == 1, 'regexp given is return too many match for column name');
                       
                [~, ia] = sort(flatjson(:, ind));
                flatjson = flatjson(ia, :);
                       
            end

            fjv.flatjson = flatjson;
            sortedfjv = fjv;

        end

        function filteredfjv = filter(fjv, filterdesc)

            if iscell(filterdesc{1})
                for ifilter = 1 : numel(filterdesc)
                    fjv = fjv.filter(filterdesc{ifilter});
                end
                filteredfjv = fjv;
                return
            end

            columnname  = filterdesc{1};
            filterval   = filterdesc{2};
            columnnames = fjv.columnnames;
            flatjson    = fjv.flatjson;

            r = regexprep(columnname, ' +', '.*');
            ind = regexp(columnnames, r);
            ind = cellfun(@(res) ~isempty(res), ind);
            ind = find(ind);
            assert(numel(ind) == 1);

            rowvals = flatjson(:, ind);
            r = regexprep(filterval, ' +', '.*');
            ind = regexp(rowvals, r);
            ind = cellfun(@(res) ~isempty(res), ind);
            ind = find(ind);

            flatjson = flatjson(ind, :);

            fjv.flatjson = flatjson;
            filteredfjv = fjv;

        end
        
    end
    
end



%{
Copyright 2021-2024 SINTEF Industry, Sustainable Energy Technology
and SINTEF Digital, Mathematics & Cybernetics.

This file is part of The Battery Modeling Toolbox BattMo

BattMo is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

BattMo is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with BattMo.  If not, see <http://www.gnu.org/licenses/>.
%}
