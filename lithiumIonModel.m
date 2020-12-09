classdef lithiumIonModel < handle
    %LITHIUMION Summary of this class goes here
    %   Detailed explanation goes here

    properties

        % Identification properties
        name        % Cell name
        serialno    % Cell serial number
        form        % Cell form factor

        % Data structure properties
        data        % Experimental data structure

        % Physical constants
        con = physicalConstants();

        % Grid
        G
        
        % Component names
        componentnames
        
        % Component properties
        elyte % Electrolyte object
        ne    % Negative electrode object
        pe    % Positive electrode object
        ccne  % Current collector object (negative electrode side)
        ccpe  % Current collector object (positive electrode side)
        
        sep   % Separator object (not included in compnames)

        % Coupling
        couplingnames
        couplingTerms
        
        % Model properties
        ...ecm
        ...spm
        ...p2d

        fv % Variable mapping structure

        % State properties
        T           % Temperature,              [K]
        A           % Cell area,                [m2]
        OCV         % Cell open circuit voltage,[V]
        U           % Cell voltage,             [V]
        Ucut        % Cutoff voltage,           [V]
        I           % Cell current,             [A]
        J           % Cell current density,     [A m^-2]
        soe         % System of equations

        % Boundary condition properties
        chargeCont  % Galvanostatic operation BC

        % Preprocessing properties
        sim
        check       % Check the simulation setup, |'on'|'off'|

        % Postprocessing properties
        display     % Display simulation output, |'final'|'monitor'|'off'|
        style       % Style for the display
        AutoDiffBackend
    end

    methods
        function obj = lithiumIonModel(varargin)
            %   Detailed explanation goes here

            if nargin == 0
                SOC = 0.5;
                T   = 298.15;
            else
                SOC = varargin(1);
                T   = varargin(2);
            end
            %% Set default simulation parameters
            obj.sim{1}        = 'dynamic';        % Definition of simulation type
            obj.sim{2}        = 'isothermal';     % Definition of simulation type
            obj.check         = 'off';            % Perform user checks during preprocessing
            obj.display       = 'final';          % Regularity of output display
            obj.style.name    = 'nightfury';      % Set style of the output
            obj.style.aspect  = 1/sqrt(2);        % Set plot aspect ratio

            %% Define battery components
            
            sepnx  = 10;
            nenx   = 10;
            penx   = 10;
            ccnenx = 5;
            ccpenx = 5;
            
            nxs = [ccnenx; nenx; sepnx; penx; ccpenx];
            ny = 10;

            xlength = 1e-6*ones(5, 1);
            ylength = 1e-6;
            
            x = xlength./nxs;
            x = rldecode(x, nxs);
            x = [0; cumsum(x)];
            
            y = ylength/ny;
            y = rldecode(y, ny);
            y = [0; cumsum(y)];
            
            G = tensorGrid(x, y);
            G = computeGeometry(G);
            obj.G = G;
            
            obj.componentnames = {'elyte', 'ne', 'pe', 'ccne', 'ccpe'};
            
            %% setup elyte
            nx = sum(nxs); 

            istart = ccnenx + 1;
            ni = nenx + sepnx + penx;
            cells = pickTensorCells(istart, ni, nx, ny);
            obj.elyte = orgLiPF6('elyte', 1000, T, G, cells);
            
            %% setup ne
            istart = ccnenx + 1;
            cells = pickTensorCells(istart, nenx, nx, ny);
            obj.ne = graphiteElectrode('ne', SOC, T, G, cells);
            
            %% setup pe
            istart = ccnenx + nenx + sepnx + 1;
            cells = pickTensorCells(istart, penx, nx, ny);
            obj.pe = nmc111Electrode('pe', SOC, T, G, cells);

            %% setup ccne
            istart = 1;
            cells = pickTensorCells(istart, ccnenx, nx, ny);
            obj.ccne = currentCollector('ccne', T, G, cells);
            
            %% setup ccpe
            istart = ccnenx + nenx + sepnx + penx + 1;
            cells = pickTensorCells(istart, ccpenx, nx, ny);
            obj.ccpe = currentCollector('ccpe', T, G, cells);

            %% setup sep 
            istart = ccnenx + nenx + 1;
            cells = pickTensorCells(istart, sepnx, nx, ny);
            obj.sep = celgard2500('sep', G, cells);

            %% setup couplings
            coupTerms = {};
            
            % coupling term 'ne-cc'
            coupTerms{end + 1} = setupNeElyteCoupTerm(obj);
            coupTerms{end + 1} = setupPeElyteCoupTerm(obj);
            coupTerms{end + 1} = setupCcneNeCoupTerm(obj);
            coupTerms{end + 1} = setupCcpePeCoupTerm(obj);
            coupTerms{end + 1} = setupCcneBcCoupTerm(obj);
            coupTerms{end + 1} = setupCcpeBcCoupTerm(obj);
            
            obj.couplingTerms = coupTerms;
            obj.couplingnames = cellfun(@(x) x.name, coupTerms, 'uniformoutput', false);
            
            %% other properties
            
            obj.OCV = obj.pe.am.OCP - obj.ne.am.OCP;
            obj.U   = obj.OCV;
            obj.T   = T;

            obj.I    = 0;
            obj.A    = 100 ./ 10000;
            obj.J    = 1;
            obj.Ucut = 2;

            obj.AutoDiffBackend = AutoDiffBackend();
            %obj.AutoDiffBackend = DiagonalAutoDiffBackend();
            %obj.AutoDiffBackend.useMex=false;
        end

        function spm(obj)
            %SPM Creates a single particle model of the Li-ion battery
            %   Detailed explanation goes here
        end

        function [dfdy, dfdyp] = odederfun(obj, t, y, yp)
            res = obj.odefun(t, y, yp, 'useAD', true);
            if(numel(res.jac)==2)
                dfdy = res.jac{1};
                dfdyp = res.jac{2};
            else
                dfdy = res.jac{1}(:,1:res.numVars(1));
                dfdyp = res.jac{1}(:,res.numVars(1)+1:end);
            end
        end

        function [t, y] = p2d(obj)

            % Generate the FV mesh
            obj.fv = fv2d(obj);
            compnames = obj.compnames;
            
            for i = 1 : numel(compnames)
                dd = ff{i};
                obj.(dd).Grid = cartGrid([obj.(dd).N], [max(obj.(dd).Xb) - min(obj.(dd).Xb)]);
                obj.(dd).Grid.nodes.coords(:, 1) = obj.(dd).Grid.nodes.coords(:, 1) + min(obj.(dd).Xb);
                obj.(dd).Grid = computeGeometry(obj.(dd).Grid);
                % We use MRST to setup discrete differential operators (Div and Grad).
                cst = ones(obj.(dd).Grid.cells.num, 1);
                rock = struct('perm', cst, 'poro', cst);
                obj.(dd).operators = setupOperatorsTPFA(obj.(dd).Grid, rock);
                obj.(dd).operators.allDiv = getAllDiv(obj.(dd).Grid);
                obj.(dd).operators.harmFace = getFaceHarmMean(obj.(dd).Grid);
                obj.(dd).operators.harmFaceBC = @(cvalue, faces) getFaceHarmBC(obj.(dd).Grid, cvalue, faces);
            end

            % Set initial conditions
            obj.icp2d();

            %% Is this constant? obj.elyte.sp.Li.Deff

            obj.elyte.sp.Li.Trans = obj.elyte.operators.harmFace(obj.elyte.sp.Li.Deff);
            obj.ne.am.Li.Trans = obj.ne.operators.harmFace(obj.ne.am.Li.Deff);
            obj.pe.am.Li.Trans = obj.pe.operators.harmFace(obj.pe.am.Li.Deff);

            % Perform manual mesh chec
            if strcmpi(obj.check, 'on')==1
                figureWindow(obj)
                plotMesh(obj)
            end

            %% Solution space (time or current) discretization

            % Time discretization
            obj.fv.ti = 0;
            obj.fv.tf = 3600*24;
            obj.fv.dt = 10;
            obj.fv.tUp = 0.1;
            obj.fv.tSpan = (obj.fv.ti:obj.fv.dt:obj.fv.tf);

            % Pre-process
            obj.dynamicPreprocess();

            % Set up and solve the system of equations
            endFun = @(t,y,yp)obj.cutOff(t,y,yp);
            fun = @(t,y,yp) obj.odefun(t, y, yp);
            derfun = @(t,y,yp) obj.odederfun(t, y, yp);

            options = odeset('RelTol'  , 1e-4  , ...
                             'AbsTol'  , 1e-6  , ...
                             'Stats'   , 'on'  , ...
                             'Events'  , endFun, ...
                             'Jacobian', derfun);

            [t, y] = ode15i(fun, obj.fv.tSpan', obj.fv.y0, obj.fv.yp0, options);

            doplot = true;
            dosave = false;
            if doplot
                resultname = 'test';
                path = 'C:\Users\simonc\Documents\01_Projects\Electrochemical Modelling Toolbox\Batteries\';
                day = date();
                hrmin = clock();
                hr = num2str(hrmin(4));
                minhr = num2str(hrmin(5));
                if dosave
                    save([path, resultname, '-', day,'-', hr,'h', minhr,'m','.mat']);
                end
                if strcmpi(obj.display, 'final')
                    plotSummary(obj,t,y);
                end
            end

        end

        function [value,isterminal,direction] = cutOff(obj,t,y,yp)
            %UNTITLED3 Summary of this function goes here
            %   Detailed explanation goes here

            %value = sum(Zn_s.Asp.*Netz.deltaX) - 0.2*sum(Zn_s.Asp_0.*Netz.deltaX);

            value = (obj.U) - obj.Ucut;
            isterminal = 1;
            direction = 0;

        end

        function icp2d(obj)

            %% Negative electrode properties

            % Temperature
            obj.ne.am.T = obj.ne.am.T .* ones(obj.ne.N, 1);

            % Volume fractions
            % Solid volume fractions
            Nne = obj.ne.N;
            obj.ne.am.eps  = obj.ne.am.eps .* ones(Nne, 1);
            obj.ne.bin.eps = obj.ne.bin.eps .* ones(Nne, 1);
            obj.ne.sei.eps = obj.ne.sei.eps .* ones(Nne, 1);
            obj.ne.eps     = obj.ne.am.eps + obj.ne.bin.eps + obj.ne.sei.eps;

            % Void volume fraction
            obj.ne.void = 1 - obj.ne.eps;

            % SEI thickness
            obj.ne.sei.t = obj.ne.sei.t .* ones(Nne, 1);

            % Lithiation
            obj.ne.am.Li.cs    = obj.ne.am.Li.cs .* ones(Nne, 1);
            obj.ne.am.Li.cseps = obj.ne.am.Li.cs .* obj.ne.am.eps;
            obj.ne.am.theta    = obj.ne.am.theta .* ones(Nne, 1);
            obj.ne.am.SOC      = obj.ne.am.SOC   .* ones(Nne, 1);

            % Open-circuit potential
            obj.ne.am.OCP = obj.ne.am.OCP .* ones(Nne, 1);
            obj.ne.am.phi = obj.ne.am.OCP;

            % Kinetic Coefficients
            obj.ne.am.k = obj.ne.am.k .* ones(Nne, 1);

            % Transport Coefficients
            obj.ne.am.Li.D    = obj.ne.am.Li.D .* ones(Nne, 1);
            obj.ne.am.Li.Deff       = obj.ne.am.Li.D .* obj.ne.am.eps.^1.5;

            %% Positive electrode properties

            Npe = obj.pe.N;
            % Temperature
            obj.pe.am.T = obj.pe.am.T .* ones(Npe, 1);

            % Volume fractions
            % Solid volume fractions
            obj.pe.am.eps  = obj.pe.am.eps .* ones(Npe, 1);
            obj.pe.bin.eps = obj.pe.bin.eps .* ones(Npe, 1);
            obj.pe.eps     = obj.pe.am.eps + obj.pe.bin.eps;
            % Void volume fraction
            obj.pe.void             = 1 - obj.pe.eps;

            % Lithiation
            obj.pe.am.Li.cs    = obj.pe.am.Li.cs .* ones(Npe, 1);
            obj.pe.am.Li.cseps = obj.pe.am.Li.cs .* obj.pe.am.eps;
            obj.pe.am.theta    = obj.pe.am.theta .* ones(Npe, 1);
            obj.pe.am.SOC      = obj.pe.am.SOC .* ones(Npe, 1);

            % Open-circuit potential
            obj.pe.am.OCP = obj.pe.am.OCP .* ones(Npe, 1);
            obj.pe.am.phi           = obj.pe.am.OCP;

            % Kinetic Coefficients
            obj.pe.am.k = obj.pe.am.k .* ones(Npe, 1);

            % Transport Coefficients
            obj.pe.am.Li.D    = obj.pe.am.Li.D .* ones(Npe, 1);
            obj.pe.am.Li.Deff = obj.pe.am.Li.D .* obj.pe.am.eps.^1.5;
            
            %% Separator properties
            obj.sep.eps             = obj.sep.eps .* ones(obj.sep.N, 1);
            obj.sep.void            = 1 - obj.sep.eps;

            %% Electrolyte properties
            obj.elyte.eps = [ obj.ne.void; obj.sep.void; obj.pe.void ];

            obj.elyte.phi        = zeros(obj.elyte.N, 1);
            obj.elyte.sp.Li.c    = obj.elyte.sp.Li.c .* ones(obj.elyte.N, 1);
            obj.elyte.sp.Li.ceps = obj.elyte.sp.Li.c .* obj.elyte.eps;
            obj.elyte.T          = obj.elyte.T .* ones(obj.elyte.N, 1);
            obj.elyte.sp.Li.D    = obj.elyte.sp.Li.D .* ones(obj.elyte.N, 1);
            obj.elyte.sp.Li.Deff = obj.elyte.sp.Li.D .* obj.elyte.eps .^1.5;
            obj.elyte.kappa      = obj.elyte.kappa .* ones(obj.elyte.N, 1);
            obj.elyte.kappaeff   = obj.elyte.kappa .* obj.elyte.eps .^1.5;

            %% Current collectors
            Ncne = obj.ccne.N;
            obj.ccne.am.OCP = obj.ne.am.OCP(1) .* ones(Ncne, 1);
            obj.ccne.am.phi = obj.ccne.am.OCP;
            obj.ccne.am.eps = obj.ccne.am.eps .* ones(Ncne, 1);

            Ncpe = obj.ccpe.N;
            obj.ccpe.am.OCP = obj.pe.am.OCP(1) .* ones(Ncpe, 1);
            obj.ccpe.am.phi = obj.ccpe.am.OCP;
            obj.ccpe.am.eps = obj.ccpe.am.eps .* ones(Ncpe, 1);

        end

        function dynamicPreprocess(obj)

            %% Initialize the state vector
            obj.ccpe.E = obj.pe.E;
            obj.fv.y0   = [ obj.elyte.sp.Li.ceps;
                            obj.elyte.phi;
                            obj.ne.am.Li.cseps;
                            obj.ne.am.phi;
                            obj.pe.am.Li.cseps;
                            obj.pe.am.phi;
                            obj.ccne.am.phi;
                            obj.ccpe.am.phi;
                            obj.ccpe.E];

            %% Inititalize the state time derivative vector
            obj.fv.yp0  = zeros(length(obj.fv.y0),1);
            
        end

        function dynamicBuildSOE(obj, t, y, yp, varargin)

            opt = struct('useAD', false);
            opt = merge_options(opt, varargin{:});
            useAD = opt.useAD;

            fv = obj.fv;

            if useAD
                adbackend = obj.AutoDiffBackend();
                [y, yp] = adbackend.initVariablesAD(y, yp);
            end

            % Mapping of variables  
            
            % elyte variables
            obj.elyte.sp.Li.ceps = y(fv.getSlot{'elyte-Li'});
            obj.elyte.phi = y(fv.getSlot{'elyte-phi'});
            % ne variables
            obj.ne.am.Li.cseps = y(fv.getSlot{'ne-Li'});
            obj.ne.am.phi = y(fv.getSlot{'ne-phi'});
            % pe variables
            obj.pe.am.Li.cseps = y(fv.getSlot{'pe-Li'});
            obj.pe.am.phi = y(fv.getSlot{'pe-phi'});
            % ccne variables
            obj.ccne.am.phi = y(fv.getSlot{'ccne-phi'});
            % ccpe variables
            obj.ccpe.am.phi = y(fv.getSlot{'ccpe-phi'});
            % voltage closure variable
            obj.ccpe.E = y(fv.getSlot{'E'});
            
            % variables for time derivatives
            obj.elyte.sp.Li.cepsdot = yp(fv.getSlot{'elyte-Li'});
            obj.ne.am.Li.csepsdot   = yp(fv.getSlot{'ne-Li'});
            obj.pe.am.Li.csepsdot   = yp(fv.getSlot{'pe-Li'});

            obj.elyte.sp.Li.c  = obj.elyte.sp.Li.ceps ./ obj.elyte.eps;
            obj.elyte.sp.PF6.c = obj.elyte.sp.Li.c;

            obj.ne.am.Li.cs = obj.ne.am.Li.cseps ./ obj.ne.am.eps;
            obj.pe.am.Li.cs = obj.pe.am.Li.cseps ./ obj.pe.am.eps;

            %% Update electrolyte physicochemical and transport properties
            obj.elyte.update()
            obj.elyte.kappaeff = obj.elyte.kappa .* obj.elyte.eps .^1.5;
            obj.elyte.sp.Li.Deff = obj.elyte.sp.Li.D .* obj.elyte.eps .^1.5;

            obj.ne.am.update()
            obj.ne.am.Li.Deff = obj.ne.am.Li.D .* obj.ne.am.eps.^1.5;
            obj.ne.sigmaeff = obj.ne.am.sigma .* obj.ne.am.eps.^1.5;

            obj.pe.am.update()
            obj.pe.am.Li.Deff = obj.pe.am.Li.D .* obj.pe.am.eps.^1.5;
            obj.pe.sigmaeff = obj.pe.am.sigma .* obj.pe.am.eps.^1.5;

            obj.ccne.sigmaeff = obj.ccne.am.sigma .* obj.ccne.am.eps.^1.5;
            obj.ccpe.sigmaeff = obj.ccpe.am.sigma .* obj.ccpe.am.eps.^1.5;

            %% Ionic current density
            % Ionic current density in the liquid
            %   Ionic current density due to the chemical potential gradient
            N = obj.elyte.N;
            ncomp = obj.elyte.ncomp;

            jchems = cell(ncomp, 1);
            for i = 1 : ncomp
                jchems{i} = zeros(N + 1, 1);
                coeff =  obj.elyte.kappaeff .* obj.elyte.ion.tvec{i} .* obj.elyte.ion.dmudc{i} ./ ...
                                     (obj.elyte.ion.zvec{i}.*obj.con.F);
                jchems{i} = obj.elyte.operators.harmFace(coeff).* obj.elyte.operators.Grad(obj.elyte.ion.cvec{i});

            end
            obj.elyte.jchem = jchems{1};
            for i = 2 : ncomp
                obj.elyte.jchem = obj.elyte.jchem + jchems{i};
            end
            %   Ionic current density due to the electrochemical potential gradient
            obj.elyte.j = obj.elyte.operators.harmFace(obj.elyte.kappaeff).*(-1).*obj.elyte.operators.Grad(obj.elyte.phi) - obj.elyte.jchem;

            %% Electric current density
            % Active material NE

            ccne = obj.ccne;
            ne = obj.ne;

            obj.ne.j = ne.operators.harmFace(ne.sigmaeff) .* (-1) .* ne.operators.Grad(ne.am.phi);
            obj.ccne.j = ccne.operators.harmFace(ccne.sigmaeff) .* (-1) .* ccne.operators.Grad(ccne.am.phi);

            % Add current transfers between ccne collector and ne material. They correspond to flux continuity
            coupterm = obj.getCoupTerm('ccne-ne');
            face_ccne = coupTerm.couplingfaces(:, 1);
            face_ne = coupTerm.couplingfaces(:, 2);
            [tne, bccell_ne] = ne.operators.harmFaceBC(ne.sigmaeff, face_ne);
            [tccne, bccell_ccne] = ccne.operators.harmFaceBC(ccne.sigmaeff, face_ccne);
            bcphi_ne = ne.am.phi(bccell_ne);
            bcphi_ccne = ccne.am.phi(bccell_ccne);

            obj.ne.j_bcsource = ne.am.phi*0.0; %NB hack to initialize zero ad
            obj.ccne.j_bcsource = ccne.am.phi*0.0; %NB hack to initialize zero ad

            t = 1./(1./tne + 1./tccne);
            crosscurrent = t.*(bcphi_ccne - bcphi_ne);
            obj.ne.j_bcsource(bccell_ne) = crosscurrent;
            obj.ccne.j_bcsource(bccell_ccne) = -crosscurrent;

            % We impose the boundary condition at chosen boundary cells of the ne current collector
            coupterm = obj.getCoupTerm('bc-ccne');
            faces = coupterm.couplingfaces;
            bcval = zeros(numel(faces), 1);
            [t, cells] = obj.ccne.operators.harmFaceBC(obj.ccne.sigmaeff, faceleft);
            obj.ccne.j_bcsource(cells) = obj.ccne.j_bcsource(cells) + t.*(bcval - obj.ccne.am.phi(cells));

            % Active material PE and current collector

            ccpe = obj.ccpe;
            pe = obj.pe;

            obj.pe.j =  pe.operators.harmFace(pe.sigmaeff) .* (-1) .* pe.operators.Grad(pe.am.phi);
            obj.ccpe.j =  ccpe.operators.harmFace(ccpe.sigmaeff) .* (-1) .* ccpe.operators.Grad(ccpe.am.phi);

            % Add current transfers between ccpe collector and pe material. They correspond to flux continuity
            coupterm = obj.getCoupTerm('ccpe-pe');
            face_ccpe = coupTerm.couplingfaces(:, 1);
            face_pe = coupTerm.couplingfaces(:, 2);
            [tpe, bccell_pe] = pe.operators.harmFaceBC(pe.sigmaeff, face_pe);
            [tccpe, bccell_ccpe] = ccpe.operators.harmFaceBC(ccpe.sigmaeff, face_ccpe);
            bcphi_pe = pe.am.phi(bccell_pe);
            bcphi_ccpe = ccpe.am.phi(bccell_ccpe);

            obj.pe.j_bcsource   = pe.am.phi*0.0; %NB hack to initialize zero ad
            obj.ccpe.j_bcsource = ccpe.am.phi*0.0; %NB hack to initialize zero ad

            t = 1./(1./tpe + 1./tccpe);
            crosscurrent = t.*(bcphi_ccpe - bcphi_pe);
            obj.pe.j_bcsource(bccell_pe) = crosscurrent;
            obj.ccpe.j_bcsource(bccell_ccpe) = -crosscurrent;

            % We impose the boundary condition at chosen boundary cells of the anode current collector
            coupterm = obj.getCoupTerm('bc-ccpe')
            faces = coupterm.couplingfaces;
            bcval = obj.ccpe.E;
            [t, cells] = obj.ccpe.operators.harmFaceBC(obj.ccpe.sigmaeff, faces);
            obj.ccpe.j_bcsource(cells) = obj.ccpe.j_bcsource(cells) + t.*(bcval - obj.ccpe.am.phi(cells));

            %% Cell voltage
            obj.ccne.E = 0;
            obj.U = obj.ccpe.E - obj.ccne.E;
            
            if useAD
                adsample = getSampleAD(y, yp);
                adbackend = obj.AutoDiffBackend;
            end

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %% Source terms for continuity equations                    %%%
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            % Inititalize vectors
            obj.elyte.sp.Li.source = zeros(obj.elyte.N, 1);
            obj.ne.am.Li.source    = zeros(obj.ne.N, 1);
            obj.pe.am.Li.source    = zeros(obj.pe.N, 1);
            obj.ne.am.e.source     = zeros(obj.ne.N, 1);
            obj.pe.am.e.source     = zeros(obj.pe.N, 1);

            if useAD
                obj.elyte.sp.Li.source = adbackend.convertToAD(obj.elyte.sp.Li.source, adsample);
                obj.ne.am.Li.source    = adbackend.convertToAD(obj.ne.am.Li.source, adsample);
                obj.pe.am.Li.source    = adbackend.convertToAD(obj.pe.am.Li.source, adsample);
                obj.ne.am.e.source     = adbackend.convertToAD(obj.ne.am.e.source, adsample);
                obj.pe.am.e.source     = adbackend.convertToAD(obj.pe.am.e.source, adsample);
            end

            % Calculate reaction rates

            % Update reaction values
            coupterm = obj.getCoupTerm('elyte-ne');
            elytecells = coupterm.couplingcells(:, 1);
            obj.ne.reactBV(obj.elyte.phi(elytecells));

            coupterm = obj.getCoupTerm('elyte-pe');
            elytecells = coupterm.couplingcells(:, 1);
            obj.pe.reactBV(obj.elyte.phi(elytecells));

            % Set up chemical source terms
            %%%%% Li+ Sources %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % Electrolyte NE Li+ source
            obj.elyte.sp.Li.source(elyte_ne.from) = +1 .* obj.ne.R;

            % Electrolyte PE Li+ source
            obj.elyte.sp.Li.source(elyte_pe.from) = -1 .* obj.pe.R;

            %%%%% Li0 Sources %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % Active Material NE Li0 source
            obj.ne.am.Li.source(elyte_ne.to) = -1 .* obj.ne.R;

            % Active Material PE Li0 source
            obj.pe.am.Li.source(elyte_pe.to) = +1 .* obj.pe.R;

            %%%%% e- Sources %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % Active Material NE Li0 source
            obj.ne.am.e.source(elyte_ne.to) = +1 .* obj.ne.R;

            % Active Material PE Li0 source
            obj.pe.am.e.source(elyte_pe.to) = -1 .* obj.pe.R;

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %% Diffusion Flux                                           %%%
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % Divergence of diffusion mass flux
            % Electrolyte Li+ Diffusion

            x = obj.elyte.sp.Li.c;
            flux = - obj.elyte.sp.Li.Trans.*obj.elyte.operators.Grad(x);
            obj.elyte.sp.Li.divDiff = obj.elyte.operators.Div(flux)./obj.elyte.Grid.cells.volumes;

            x= obj.ne.am.Li.cs;
            flux = - obj.ne.am.Li.Trans.*obj.ne.operators.Grad(x);
            obj.ne.am.Li.divDiff =  obj.ne.operators.Div(flux)./obj.ne.Grid.cells.volumes;

            x = obj.pe.am.Li.cs;
            flux = - obj.pe.am.Li.Trans.*obj.pe.operators.Grad(x);
            obj.pe.am.Li.divDiff = obj.pe.operators.Div(flux)./obj.pe.Grid.cells.volumes;

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %% Migration Flux                                           %%%
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % Divergence of the migration mass flux
            %   Electrolyte Li+ Migration
            flux = obj.elyte.sp.Li.t ./ (obj.elyte.sp.Li.z .* obj.con.F) .* obj.elyte.j;

            obj.elyte.sp.Li.divMig = obj.elyte.operators.Div(flux)./obj.elyte.Grid.cells.volumes;

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %% System of Equations                                      %%%
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            %% Liquid electrolyte dissolved ionic species mass continuity %
            %   Electrolyte Li+ Mass Continuity
            obj.elyte.sp.Li.massCont = ( - obj.elyte.sp.Li.divDiff - obj.elyte.sp.Li.divMig + obj.elyte.sp.Li.source ...
                                         - obj.elyte.sp.Li.cepsdot);

            %% Liquid electrolyte charge continuity %%%%%%%%%%%%%%%%%%%%%%%

            obj.elyte.chargeCont = -(obj.elyte.operators.Div( obj.elyte.j)./obj.elyte.Grid.cells.volumes) ./ obj.con.F+ ...
                obj.elyte.sp.Li.source .* obj.elyte.sp.Li.z;

            %% Active material mass continuity %%%%%%%%%%%%%%%%%%%%%%%%%%%
            obj.ne.am.Li.massCont = (-obj.ne.am.Li.divDiff + obj.ne.am.Li.source - obj.ne.am.Li.csepsdot);
            obj.pe.am.Li.massCont = (-obj.pe.am.Li.divDiff + obj.pe.am.Li.source - obj.pe.am.Li.csepsdot);

            %% Active material charge continuity %%%%%%%%%%%%%%%%%%%%%%%%%%%

            obj.ne.am.e.chargeCont = (obj.ne.operators.Div(obj.ne.j) - obj.ne.j_bcsource)./ ...
                obj.ne.Grid.cells.volumes./obj.con.F - obj.ne.am.e.source;
            obj.pe.am.e.chargeCont = (obj.pe.operators.Div(obj.pe.j) - obj.pe.j_bcsource)./ ...
                obj.pe.Grid.cells.volumes./obj.con.F - obj.pe.am.e.source;

            obj.ccne.am.e.chargeCont = (obj.ccne.operators.Div(obj.ccne.j) - obj.ccne.j_bcsource)./ ...
                obj.ccne.Grid.cells.volumes./obj.con.F;
            obj.ccpe.am.e.chargeCont = (obj.ccpe.operators.Div(obj.ccpe.j) - obj.ccpe.j_bcsource)./ ...
                obj.ccpe.Grid.cells.volumes./obj.con.F;

            src = currentSource(t, fv.tUp, fv.tf, obj.J);
            faceright = obj.pe.Grid.faces.num;
            bcright = obj.ccpe.E;
            [t, cells] = obj.ccpe.operators.harmFaceBC(obj.ccpe.sigmaeff, faceright);
            control = src - t.*(bcright - obj.ccpe.am.phi(cells));

            %% State vector %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            obj.soe = vertcat(obj.elyte.sp.Li.massCont, ...
                              obj.elyte.chargeCont    , ...
                              obj.ne.am.Li.massCont   , ...
                              obj.ne.am.e.chargeCont  , ...
                              obj.pe.am.Li.massCont   , ...
                              obj.pe.am.e.chargeCont  , ...
                              obj.ccne.am.e.chargeCont, ...
                              obj.ccpe.am.e.chargeCont, ...
                              control);

        end

        function res = odefun(obj, t, y, yp, varargin)
        %ODEFUN Compiles the system of differential equations

            opt = struct('useAD', false);
            opt = merge_options(opt, varargin{:});
            useAD = opt.useAD;

            dodisplay = false;
            if dodisplay
                % Display current time step
                clc
                disp('Time, s:')
                disp(t)
                disp('Current Density, A/cm2:')
                disp(-1e-4.*currentSource(t, obj.fv.tUp, obj.fv.tf, obj.J))
                disp('Cell Voltage, V:')
                disp(obj.ccpe.E - obj.ccne.E)
            end

            % Build SOE
            obj.dynamicBuildSOE(t, y, yp, 'useAD', useAD);

            res = obj.soe;
        end
        
        function coupterm = getCoupTerm(obj, coupname)
            coupnames = obj.couplingnames;
            
            [isok, ind] = ismember(coupname, coupnames);
            assert(isok, 'name of coupling term is not recognized.');
            
            coupterm = obj.couplingTerms{ind};
            
        end
      
        
        function coupTerm = setupNeElyteCoupTerm(obj)
            Gelyte = obj.elyte.Grid;
            Gne = obj.ne.Grid;
            
            % parent Grid
            G = Gne.mappings.parentGrid;
            
            % All the cells from ne are coupled with elyte
            cells1 = (1 : Gne.cells.num)';
            pcells = Gne.mappings.cellmap(cells1);
            
            mapping = zeros(G.cells.num, 1);
            mapping(Gelyte.mappings.cellmap) = (1 : Gelyte.cells.num)';
            cells2 = mapping(pcells);
            
            compnames = {'ne', 'elyte'};
            coupTerm = couplingTerm('ne-elyte', compnames);
            coupTerm.couplingcells =  [cells1, cells2];
            coupTerm.couplingfaces = []; % no coupling throug faces. We set it as empty
            
        end
            
        function coupTerm = setupPeElyteCoupTerm(obj)
            
            Gelyte = obj.elyte.Grid;
            Gpe = obj.pe.Grid;
            
            % parent Grid
            G = Gpe.mappings.parentGrid;
            
            % All the cells from pe are coupled with elyte
            cells1 = (1 : Gpe.cells.num)';
            pcells = Gpe.mappings.cellmap(cells1);
            
            mapping = zeros(G.cells.num, 1);
            mapping(Gelyte.mappings.cellmap) = (1 : Gelyte.cells.num)';
            cells2 = mapping(pcells);
            
            compnames = {'pe', 'elyte'};
            coupTerm = couplingTerm('pe-elyte', compnames);
            coupTerm.couplingcells = [cells1, cells2];
            coupTerm.couplingfaces = []; % no coupling between faces
            
        end
            
        function coupTerm = setupCcneNeCoupTerm(obj)
            
            Gccne = obj.ccne.Grid;
            Gne = obj.ne.Grid;
            
            % parent Grid
            G = Gne.mappings.parentGrid;
            
            % We pick up the faces at the right of Cccne
            xf = Gccne.faces.centroids(:, 1);
            mxf = max(xf);
            faces1 = find(xf > (1 - eps)*mxf);
            
            pfaces = Gccne.mappings.facemap(faces1);
            mapping = zeros(G.faces.num, 1);
            mapping(Gne.mappings.facemap) = (1 : Gne.faces.num)';
            faces2 = mapping(pfaces);
            
            cells1 = sum(Gccne.faces.neighbors(faces1, :), 2);
            cells2 = sum(Gne.faces.neighbors(faces2, :), 2);
            
            compnames = {'ccne', 'ne'};
            coupTerm = couplingTerm('ccne-ne', compnames);
            coupTerm.couplingfaces =  [faces1, faces2];
            coupTerm.couplingcells = [cells1, cells2];
            
        end
            
        function coupTerm = setupCcpePeCoupTerm(obj)
            Gccpe = obj.ccpe.Grid;
            Gpe = obj.pe.Grid;
            
            % parent Grid
            G = Gpe.mappings.parentGrid;
            
            % We pick up the faces at the left of Cccpe
            xf = Gccpe.faces.centroids(:, 1);
            mxf = min(xf);
            faces1 = find(xf < (1 + eps)*mxf);
            
            pfaces = Gccpe.mappings.facemap(faces1);
            mapping = zeros(G.faces.num, 1);
            mapping(Gpe.mappings.facemap) = (1 : Gpe.faces.num)';
            faces2 = mapping(pfaces);
            
            cells1 = sum(Gccpe.faces.neighbors(faces1, :), 2);
            cells2 = sum(Gpe.faces.neighbors(faces2, :), 2);
            
            compnames = {'ccpe', 'pe'};
            coupTerm = couplingTerm('ccpe-pe', compnames);
            coupTerm.couplingfaces =  [faces1, faces2];
            coupTerm.couplingcells = [cells1, cells2];
            
        end
            
        function coupTerm = setupCcneBcCoupTerm(obj)
            
            G = obj.ccne.Grid;
            % We pick up the faces at the top of Cccne
            yf = G.faces.centroids(:, 2);
            myf = max(yf);
            faces = find(yf > (1 - eps)*myf);            
            cells = sum(G.faces.neighbors(faces, :), 2);
            
            compnames = {'ccne'};
            coupTerm = couplingTerm('bc-ccne', compnames);
            coupTerm.couplingfaces = faces;
            coupTerm.couplingcells = cells;
        
        end
           
        function coupTerm = setupCcpeBcCoupTerm(obj)
            
            G = obj.ccpe.Grid;
            % We pick up the faces at the top of Cccpe
            yf = G.faces.centroids(:, 2);
            myf = max(yf);
            faces = find(yf > (1 - eps)*myf);            
            cells = sum(G.faces.neighbors(faces, :), 2);
            
            compnames = {'ccpe'};
            coupTerm = couplingTerm('bc-ccpe', compnames);
            coupTerm.couplingfaces = faces;
            coupTerm.couplingcells = cells;
        
        end
            
    end

end

function [T, cells] = getFaceHarmBC(G, cvalue, faces)
    cells = sum(G.faces.neighbors(faces, :), 2);
    cn = sqrt(sum((G.faces.centroids(faces, :) - G.cells.centroids(cells, :)).^2, 2));
    t = G.faces.areas(faces)./cn;
    T = t.*cvalue(cells);
end

function hm = getFaceHarmMean(G)
    internal = all(G.faces.neighbors>0, 2);
    N = G.faces.neighbors(internal, :);
    ni = sum(internal);
    cd = sqrt(sum((G.cells.centroids(N(:, 1), :) - G.cells.centroids(N(:, 2), :)).^2, 2)); % NB
    t = G.faces.areas(internal)./cd;
    A = sparse([[1:ni]'; [1:ni]'], N, 1, ni, G.cells.num);
    hm = @(cellvalue) 2.*t./(A*(1./cellvalue));
end

function tp = getTwoPointOperator(G)
% Mappings from cells to its faces
    cells = rldecode(1:G.cells.num, diff(G.cells.facePos), 2)';
    faces = G.cells.faces(:, 1);
    % Vector from cell to face centroid
    C = G.faces.centroids(faces, :) - G.cells.centroids(cells, :);
    % Oriented normals
    sgn = 2*(cells == G.faces.neighbors(faces, 1)) - 1;
    N = bsxfun(@times, sgn, G.faces.normals(faces, :));
    % Make function
    cn = sum(C.*N, 2)./sum(C.*C, 2);
    tp = @(lambda) cn.*lambda(cells);
end

function ha = getHarmonicAvgOperator(G)
% Harmonic averaging operator
    faces = G.cells.faces(:, 1);
    M = sparse(faces, 1:numel(faces), 1, G.faces.num, numel(faces));
    ha = @(T) 1./(M*(1./T));
end

function allDiv = getAllDiv(G)
    nc = G.cells.num;
    nf = G.faces.num;
    Nall = G.faces.neighbors;
    internal = all(Nall>0, 2);
    ifn = find(internal);
    efn = find(~internal);
    inf = numel(ifn);
    N = Nall(internal, :);
    Nb = Nall(~internal, :);
    signb = 2*(Nb(:, 1)>0) - 1;
    Nb = sum(Nb, 2);
    C = sparse([ifn; ifn], N, ones(inf, 1) * [1,- 1], nf, nc);
    C = C + sparse(efn, Nb, signb, nf, nc);
    allDiv = @(x) (C'*x)./G.cells.volumes;
end

function plotMesh(obj)

    subplot(3,1,1), plot(obj.fv.Xb.*1e3, zeros(size(obj.fv.Xb)),'+','MarkerSize',5, 'LineWidth',2, 'Color', obj.style.palette.discrete(1,:));
    hold on
    plot(obj.fv.X.*1e3, zeros(size(obj.fv.X)),'o','MarkerSize',5, 'LineWidth',2, 'Color', obj.style.palette.discrete(7,:));
    hold off
    xlim([min(obj.fv.Xb), obj.fv.Xb(10)].*1e3);
    set(gca,'FontSize',28, ...
            'color',obj.style.background, ...
            'ColorOrder', obj.style.palette.discrete)
    ax = gca;
    ax.XColor = 'w';
    ax.YColor = 'w';
    title('Finite Volume Mesh: Left Bound', 'Color', 'w')

    subplot(3,1,2), plot(obj.fv.Xb.*1e3, zeros(size(obj.fv.Xb)),'+','MarkerSize',5, 'LineWidth',2, 'Color', obj.style.palette.discrete(1,:));
    hold on
    plot(obj.fv.X.*1e3, zeros(size(obj.fv.X)),'o','MarkerSize',5, 'LineWidth',2, 'Color', obj.style.palette.discrete(7,:));
    hold off
    xlim([min(obj.fv.Xb), max(obj.fv.Xb)].*1e3);
    set(gca,'FontSize',28, ...
            'color',obj.style.background, ...
            'ColorOrder', obj.style.palette.discrete)
    ax = gca;
    ax.XColor = 'w';
    ax.YColor = 'w';
    title('Finite Volume Mesh: Whole Domain', 'Color', 'w')

    subplot(3,1,3), plot(obj.fv.Xb.*1e3, zeros(size(obj.fv.Xb)),'+','MarkerSize',5, 'LineWidth',2, 'Color', obj.style.palette.discrete(1,:));
    hold on
    plot(obj.fv.X.*1e3, zeros(size(obj.fv.X)),'o','MarkerSize',5, 'LineWidth',2, 'Color', obj.style.palette.discrete(7,:));
    hold off
    xlim([obj.fv.Xb(end-10), max(obj.fv.Xb)].*1e3);
    set(gca,'FontSize',28, ...
            'color',obj.style.background, ...
            'ColorOrder', obj.style.palette.discrete)
    ax = gca;
    ax.XColor = 'w';
    ax.YColor = 'w';
    title('Finite Volume Mesh: Right Bound', 'Color', 'w')
    hold off
    xlabel('Location  /  mm')

end

function plotElyteConcentration(obj, varargin)

    if isempty(varargin)
        plot(obj.fv.X.*1e3, obj.elyte.sp.Li.c.*1e-3, 'LineWidth', 5)
        xlabel('Position  /  mm')
        ylabel('LiPF_6 Conc.  /  mol\cdotL^{-1}')
        eval(obj.style.name)
    end

end

function plotElytePotential(obj, varargin)

    if isempty(varargin)
        plot(obj.fv.X.*1e3, obj.elyte.phi, 'LineWidth', 5)
        xlabel('Position  /  mm')
        ylabel('Electric Potential  /  V')
        eval(obj.style.name)
    end

end

function plotPotentials(obj, varargin)

    if isempty(varargin)
        plot(obj.fv.X.*1e3, obj.elyte.phi, 'LineWidth', 5)
        hold on
        plot(obj.ne.X.*1e3, obj.ne.am.phi, 'LineWidth', 5)
        plot(obj.pe.X.*1e3, obj.pe.am.phi, 'LineWidth', 5)
        xlabel('Position  /  mm')
        ylabel('Electric Potential  /  V')
        eval(obj.style.name)
    end

end

function plotCurrentDensity(obj, varargin)

    if isempty(varargin)
        plot(obj.fv.Xb.*1e3, obj.elyte.j, 'LineWidth', 5)
        hold on
        plot(obj.ne.Xb.*1e3, obj.ne.j, 'LineWidth', 5)
        plot(obj.pe.Xb.*1e3, obj.pe.j, 'LineWidth', 5)
        xlabel('Position  /  mm')
        ylabel('Current Density  /  A m^{-2}')
        eval(obj.style.name)
    end

end

function plotSummary(obj,t,y,varargin)

    close all

    if ~isempty(varargin)
        teval = varargin;
        [~,~,idt]=unique(round(abs(t-teval)),'stable');
    else
        idt = length(t);
    end

    Epe = y(:, obj.fv.s8);
    Epe = Epe(:, end);
    figure(1), plot(t./3600, Epe -obj.ne.E, 'LineWidth', 5)
    ylim([2, 4.2])
    xlabel('Time  /  h')
    ylabel('Cell Voltage  /  V')
    eval(obj.style.name)

    figure(2)
    subplot(2,3,1:3), plot(obj.elyte.X.*1e3, 1e-3.*y(idt, obj.fv.s1)./obj.elyte.eps', 'LineWidth', 5)
    xlabel('Position  /  mm')
    ylabel('LiPF_6 Conc.  /  mol\cdotL^{-1}')
    eval([obj.style.name, '("subplot")'])
    set(gca, 'FontSize', 14)

    subplot(2,3,4), plot(obj.ne.X.*1e3, y(idt, obj.fv.s3)./obj.ne.am.eps' ./ obj.ne.am.Li.cmax, 'LineWidth', 5)
    xlabel('Position  /  mm')
    %ylabel('Li Conc.  /  mol\cdotL^{-1}')
    eval([obj.style.name, '("subplot")'])
    set(gca, 'FontSize', 14)

    subplot(2,3,6), plot(obj.pe.X.*1e3, y(idt, obj.fv.s5)./obj.pe.am.eps'./ obj.pe.am.Li.cmax, 'LineWidth', 5)
    xlabel('Position  /  mm')
    %ylabel('Li Conc.  /  mol\cdotL^{-1}')
    eval([obj.style.name, '("subplot")'])
    set(gca, 'FontSize', 14)

    figure(3)
    subplot(2,3,1:3), plot(obj.elyte.X.*1e3, y(idt, obj.fv.s2), 'LineWidth', 5)
    xlabel('Position  /  mm')
    ylabel('Electric Potential  /  V')
    eval([obj.style.name, '("subplot")'])
    set(gca, 'FontSize', 14)

    subplot(2,3,4), plot(obj.ne.X.*1e3, y(idt, obj.fv.s4), 'LineWidth', 5)
    xlabel('Position  /  mm')
    %ylabel('Li Conc.  /  mol\cdotL^{-1}')
    eval([obj.style.name, '("subplot")'])
    set(gca, 'FontSize', 14)

    subplot(2,3,6), plot(obj.pe.X.*1e3, y(idt, obj.fv.s6), 'LineWidth', 5)
    xlabel('Position  /  mm')
    %ylabel('Li Conc.  /  mol\cdotL^{-1}')
    eval([obj.style.name, '("subplot")'])
    set(gca, 'FontSize', 14)

end

function figureWindow(obj,font)
    figure()
    set(gca,'FontSize',28, ...
            'color',obj.style.background, ...
            'ColorOrder', obj.style.palette.discrete)
    ax = gca;
    ax.XColor = 'w';
    ax.YColor = 'w';
    set(gcf,'units','centimeter',...
            'position',[5,5,obj.style.width,obj.style.height], ...
            'color',obj.style.background)
    if nargin < 2
        set(gca, 'FontName', 'Helvetica')
    elseif srtcmpi(font, 'serif') == 1
        set(gca, 'FontName', 'Baskerville Old Face')
    else
        set(gca, 'FontName', 'Helvetica')
    end
    hold on
end

function cells = pickTensorCells(istart, ni, nx, ny)
    cells = (istart : (istart + ni - 1));
    cells = repmat(cells, ny, 1);
    cells = bsxfun(@plus, nx*(0 : (ny - 1))', cells);
    cells = reshape(cells', [], 1);
end
