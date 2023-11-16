classdef PEMgridGenerator1D < PEMgridGenerator


    properties

        % Length
        xlength
        % Discretization number
        N
        % Section area
        faceArea 
        
    end
    
    methods

        function gen = PEMgridGenerator1D()
            
            gen = gen@PEMgridGenerator();
            
        end

        function [paramobj, gen] = updatePEMinputParams(gen, paramobj, params)

            paramobj = gen.setupPEMinputParams(paramobj, []);
            
            elyte = 'Electrolyte';
            
            paramobj.G         = gen.adjustGridToFaceArea(paramobj.G);
            paramobj.(elyte).G = gen.adjustGridToFaceArea(paramobj.(elyte).G);
            
            paramobj.dx    = gen.xlength/gen.N;
            paramobj.faceArea = gen.faceArea;
            
        end

        function [paramobj, gen] = setupGrid(gen, paramobj, params)
            
            G = cartGrid(gen.N, gen.xlength);
            G = computeGeometry(G);
            
            paramobj.G = G;
            gen.G = G;
            
        end
        
        function paramobj = setupElectrolyte(gen, paramobj, params)
        % Method that setups the grid and the coupling for the electrolyte model

            params.cellind = (1 : gen.N)';
            paramobj = setupElectrolyte@PEMgridGenerator(gen, paramobj, params);
            
        end

        function paramobj = setupElectrodeElectrolyteCoupTerm(gen, paramobj, params)

            an    = 'Anode';
            ct    = 'Cathode';
            elyte = 'Electrolyte';

            G = paramobj.G;
            
            params.(an).couplingcells = 1;
            params.(an).couplingfaces = 1;
            params.(ct).couplingcells = G.cells.num;
            params.(ct).couplingfaces = G.faces.num;

            paramobj = setupElectrodeElectrolyteCoupTerm@PEMgridGenerator(gen, paramobj, params);
            
        end

        function G = adjustGridToFaceArea(gen, G);

            fa = gen.faceArea;

            G.faces.areas   = fa*G.faces.areas;
            G.faces.normals = fa*G.faces.normals;
            G.cells.volumes = fa*G.cells.volumes;

        end
        
    end
    
    
end
