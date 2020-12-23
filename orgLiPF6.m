classdef orgLiPF6 < SimpleModel
%orgLiPF6 An electrolyte class for electrochemical modelling
%   The orgLiPF6 class describes the properties and
%   parameterization for organic electrolytes featuring lithium
%   hexafluorophosphate (LiPF6) salt dissolved in an alykl-carbonate
%   solvent. Common solvent materials are: 
%
%   PC          Propylene Carbonate     (ChemSpider ID: 7636)
%   EC          Ethylene Carbonate      (ChemSpider ID: 7030)
%   EMC         Ethyl Methyl Carbonate  (ChemSpider ID: 455390)
%   DMC         Dimethyl Carbonate      (ChemSpider ID: 11526)
%
%   The class calculates electrolyte properties based on experimental
%   parameterization studies described in the scientific literature.
%   The validity of the parameterization is limited to the conditions
%   in which it was reported.
%
%   Author: Simon Clark (simon.clark@sintef.no)
%   Usage:  This code is free to use "as-is" for the purpose of 
%           research at SINTEF without warranty of any kind. The code
%           is provided with the hope that it will be helpful. The 
%           author assumes no liability.         
%
%   Acknowledgement: This code builds on the work of many other
%   scientists over decades of research. Their work is gratefully
%   acknowledged and cited throughout the code. 
%
%   Revision History:
%       03.06.2020: SC (simon.clark@sintef.no) - New Energy Solutions 
%                   Initial version (0.0-alpha)
    
    properties
        % Identification properties
        sp      % Dissolved species data structure
        ion     % Dissolved ionic species data structure
        solv    % Solvent data structure

        % number of components
        
        compnames % 2 components in this implementation : Li and PF6 (can be generalized)
        ncomp % number of components
        
        
        % Physical constants
        con = physicalConstants();
        

        % Physicochemical properties
        rho         % Mass Density,                         [kg m^-3]
        mu          % Viscosity             
        kappaeff    % Porous media conductivity,            [S m^-1]
        lambda      % Thermal conductivity,                 [W m^-1 K^-1]
        lambdaeff   % Porous media thermal conductivity,    [W m^-1 K^-1]
        cp          % Heat Capacity
        sigma       % Surface Tension
        pvap        % Vapor Pressure    
        Deff        % Porous media diffusion coefficient,   [m^2 s^-1]
        
        % Finite volume solution properties
        chargeCont

        
    end
    
    methods
        
        function model = orgLiPF6(name, G, cells)
            
            model = model@SimpleModel(name);
            model.G = genSubGrid(G, cells);
            model.compnames = {'Li', 'PF6'};
            model.ncomp = numel(model.compnames);
            
            % primary variables
            names = {'phi', 'c_Li'}; % name 'c_Li' should match the setup in getAffiliatedComponentNames
            model.pnames = names;
            
            % state variables
            [concnames, ionconcnames, jchemnames, dmudcnames] = model.getAffiliatedComponentNames();
            % note that the 'c_Li' variable has been removed from concnames in method getAffiliatedComponentNames
            names = {'phi', ...   
                     'm', ...     % Molality,              [mol kg^-1]
                     'kappa', ... % Conductivity,          [S m^-1]
                     'D', ...     % Diffusion coefficient, [m^2 s^-1]
                     'wtp', ...   % Weight percentace,     [wt%]
                     'eps', ...   % Volume fraction,       [-]
                     'IoSt', ...  % Ionic strength
                     'j' ...      % Ionic current density
                    };
            
            model.names = horzcat(concnames, ionconcnames, jchemnames, dmudcnames, names);
            
            model.aliases = {{'T', VarName({}, 'T')}};
            
        end

        function state = initializeState(model, state)

            state = model.validateState(state);
            
            nc = model.G.cells.num;
            compnames = model.compnames;

            state = model.setProp(state, 'phi', zeros(nc, 1));
            
            c = model.getProp(state, 'c_Li');
            state = model.setProp(state, 'c_PF6', c);
            
            % Set constant values
            [~, ind] = ismember('Li', compnames);
            tLi = 0.399;
            model.sp.t{ind} = tLi;           % Li+ transference number, [-]
            model.sp.z{ind} = 1;
            
            [~, ind] = ismember('PF6', compnames);
            model.sp.t{ind} = 1 - tLi;           % Li+ transference number, [-]
            model.sp.z{ind} = -1;
            
            state = model.update(state);
            
        end
        
        
        function state = update(model, state)
            state = model.updateIonicQuantities(state);
            state = model.updateConductivity(state);
            state = model.updateDiffusion(state);
        end

        function [concnames, ionconcnames, jchemnames, dmudcnames] = getAffiliatedComponentNames(model, varargin)
            
            opt = struct('init', false);
            opt = merge_options(opt, varargin{:});
            
            compnames = model.compnames;
            
            concnames    = cellfun(@(x) sprintf('c_%s', x), compnames, 'uniformoutput', false);
            ionconcnames = cellfun(@(x) sprintf('ionc_%s', x), compnames, 'uniformoutput', false);            
            jchemnames   = cellfun(@(x) sprintf('jchem_%s', x), compnames, 'uniformoutput', false);
            dmudcnames   = cellfun(@(x) sprintf('dmucd_%s', x), compnames, 'uniformoutput', false);
        end
        
        function state = updateIonicQuantities(model, state)
            
            T = model.getProp(state, 'T');
            
            ncomp = model.ncomp;
            [concnames, ionconcnames, jchemnames, dmudcnames] = getAffiliatedComponentNames(model);
            
            for ind = 1 : ncomp
                cname     = concnames{ind};
                ionname   = ionconcnames{ind};
                dmudcname = dmudcnames{ind};            
                
                cvec{ind} = model.getProp(state, cname);
                
                dmudc = model.con.R .* T ./ cvec{ind};
                
                state = model.setProp(state, ionname, cvec{ind});
                state = model.setProp(state, dmudcname, dmudc);
                
            end

            % this part is specific to 2 component system
            IoSt = 0.5 .* cvec{1}.*model.sp.z{1}.^2./1000;
            IoSt = IoSt + 0.5 .* cvec{2}.*model.sp.z{2}.^2./1000;
            
            state = model.setProp(state, 'IoSt', IoSt);
            
        end
        
        function state = updateConductivity(model, state)
        %   conductivity Calculates the ionic conductivity of the
        %   eletrolyte in units [S m^-1].
        %   Electrolyte conductivity according to the model proposed by
        %   Val�en et al [1]. The model was made by performing a
        %   least-squares fit of experimental data with LiPF6 
        %   concenrations from 7.7e-6 M to 3.9 M and temperatures from
        %   263 K to 333 K. The solvent is 10 vol% PC, 27 vol% EC, 63
        %   vol% DMC.
            
        % Empirical fitting parameters
            cnst = [-10.5   ,    0.074    ,    -6.96e-5; ...
                    0.668e-3,    -1.78e-5 ,    2.80e-8; ...
                    0.494e-6,    -8.86e-10,    0];
            
            % Electrolyte conductivity
            T = model.getProp(state, 'T');
            c = model.getProp(state, 'c_Li');
            
            kappa = 1e-4 .* c .* (...
                (cnst(1,1) + cnst(2,1) .* c + cnst(3,1) .* c.^2) + ...
                (cnst(1,2) + cnst(2,2) .* c + cnst(3,2) .* c.^2) .* T + ...
                (cnst(1,3) + cnst(2,3) .* c) .* T.^2) .^2;
            
            state = model.setProp(state, 'kappa', kappa);
            
        end
        
        function state = updateDiffusion(model, state)
        %   diffusion Calculates the diffusion coefficient of Li+ ions in
        %   the electrolyte in units [m2 s^-1].
        %   Diffusion coefficient according to the model proposed by
        %   Val�en et al [1]. The model was made by performing a
        %   least-squares fit of experimental data with LiPF6 
        %   concenrations from 7.7e-6 M to 3.9 M and temperatures from
        %   263 K to 333 K. The solvent is 10 vol% PC, 27 vol% EC, 63
        %   vol% DMC.
            
        % Empirical fitting parameters [1]
            cnst = [ -4.43, -54;
                     -0.22, 0.0 ];
            Tgi = [ 229;
                    5.0 ];
            
            T = model.getProp(state, 'T');
            c = model.getProp(state, 'c_Li');
            
            % Diffusion coefficient, [m^2 s^-1]
            D = 1e-4 .* 10 .^ ( ( cnst(1,1) + cnst(1,2) ./ ( T - Tgi(1) - Tgi(2) .* c .* 1e-3) + cnst(2,1) .* ...
                                  c .* 1e-3) );
            
            state = model.setProp(state, 'D', D);
            
        end
        
        
    end

    %% References
    %
    %   [1] Journal ofThe Electrochemical Society, 152 (5) A882-A891 (2005),
    %   DOI: 10.1149/1.1872737



end

