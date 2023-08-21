classdef SubGrid

    properties

        % Parent grid 
        % The parent grid contains the updated TwoPointFiniteVolumeGeometry values (handle)
        parentGrid % Instance of Grid class

        % Description of the topology of the sub-grid using MRST grid structures: The fieds are
        % - topology.cells.facePos
        % - topology.cells.faces
        % - topology.cells.num
        % - topology.faces.nodePos
        % - topology.faces.nodes
        % - topology.faces.num
        % - topology.faces.neighbors
        % - topology.nodes.num
        % - topology.griddim        
        topology
        
        % Mapping structure from sub-grid to parent grid with fields (see function removeCells)
        % - mappings.cellmap
        % - mappings.facemap
        % - mappings.nodemap
        mappings

        % Helper structures that are used to extract the half-transmissibilities from the parent structures and assemble the
        % fluxes, with fields
        % - helpers.diffop.grad                 (sparse matrix used in getGradient)
        % - helpers.diffop.div                  (sparse matrix used in getDiv)
        % - helpers.trans.D                     (sparse matrix used in getFlux method)
        % - helpers.trans.P                     (sparse matrix used in getFlux method)
        % - helpers.trans.S                     (sparse matrix used in getFlux method)
        % - helpers.extfaces.faces              (index of the external faces, sub-grid indexing)
        % - helpers.extfaces.cells              (index of the corresponding cells, sub-grid indexing)
        % - helpers.extfaces.halfTransParentInd (index of the corresponding half-transmissibility values in parent grid indexing)
        % - helpers.faceextfacemap              (mapping from face to extface, sub-grid indexing)
        helpers

        % Operators to compute norm of the flux velocity at the cell centers, see getCellFlux 
        % - cellFluxOperators.P
        % - cellFluxOperators.S
        cellFluxOperators
        
    end

    methods

        function subG = SubGrid(G, parentGrid, mappings)
        % We initiate the subgrid using a MRST grid with the parentGrids and the mappings

            topology.cells.facePos   = G.cells.facePos;
            topology.cells.faces     = G.cells.faces;
            topology.cells.num       = G.cells.num;
            topology.faces.nodePos   = G.faces.nodePos;
            topology.faces.nodes     = G.faces.nodes;
            topology.faces.num       = G.faces.num;
            topology.faces.neighbors = G.faces.neighbors;
            topology.nodes.num       = G.nodes.num;
            topology.griddim         = G.griddim;
            
            subG.topology   = topology;
            subG.parentGrid = parentGrid;
            subG.mappings   = mappings;

            subG = subG.setupHelpers();
            
        end


        function subG = setupHelpers(subG)

            ptbls = setupTables(subG.parentGrid.topology);
            pcellpfacetbl = ptbls.cellfacetbl;

            tbls  = setupTables(subG.topology, 'includetbls', {'cellintfacetbl', 'extfacetbl'});
            celltbl        = tbls.celltbl;
            facetbl        = tbls.facetbl;
            extfacetbl     = tbls.extfacetbl;
            intfacetbl     = tbls.intfacetbl;
            cellintfacetbl = tbls.cellintfacetbl;
            
            sgn = ones(cellintfacetbl.num, 1);
            f = cellintfacetbl.get('faces');
            c = cellintfacetbl.get('cells');
            sgn(subG.topology.faces.neighbors(f, 1) == c) = -1;

            prod = TensorProd();
            prod.tbl1 = cellintfacetbl;
            prod.tbl2 = intfacetbl;
            prod.tbl3 = celltbl;
            prod.reducefds = {'faces'};
            prod = prod.setup;

            divM = SparseTensor();
            divM = divM.setFromTensorProd(sgn, prod);
            divM = divM.getMatrix();

            diffop.div  = divM;
            diffop.grad = -divM';
            
            cellpcelltbl = celltbl.addInd('pcells', subG.mappings.cellmap);
            facepfacetbl = facetbl.addInd('pfaces', subG.mappings.facemap);

            pcellpfacetbl = replacefield(pcellpfacetbl, {{'cells', 'pcells'}, {'faces', 'pfaces'}});
            
            cellpcellpfacetbl     = crossIndexArray(pcellpfacetbl, cellpcelltbl, {'pcells'});
            cellpcellfacepfacetbl = crossIndexArray(cellpcellpfacetbl, facepfacetbl, {'pfaces'});

            % We need the following mapping as the creation of cellpcellfacepfacetbl do not guarantee that index
            % ordering is preserved.
            map1 = TensorMap();
            map1.fromTbl = pcellpfacetbl;
            map1.toTbl = cellpcellfacepfacetbl;
            map1.mergefds = {'pcells', 'pfaces'};
            map1 = map1.setup();

            P1 = map1.getMatrix();
            
            map2 = TensorMap();
            map2.fromTbl = cellpcellfacepfacetbl;
            map2.toTbl = cellintfacetbl;
            map2.mergefds = {'cells', 'faces'};
            map2 = map2.setup();

            P2 = map2.getMatrix();

            P = P2*P1;
            
            map = TensorMap();
            map.fromTbl = celltbl;
            map.toTbl = cellintfacetbl;
            map.mergefds = {'cells'};
            map = map.setup();

            D = map.getMatrix();
            
            map = TensorMap();
            map.fromTbl = cellintfacetbl;
            map.toTbl = intfacetbl;
            map.mergefds = {'faces'};
            map = map.setup();

            S = map.getMatrix();

            trans = struct('P', P, ...
                           'D', D, ...
                           'S', S);

            extfacepfacetbl          = crossIndexArray(extfacetbl, facepfacetbl, {'faces'});
            extfacepcellpfacetbl     = crossIndexArray(extfacepfacetbl, pcellpfacetbl, {'pfaces'});
            cellextfacepcellpfacetbl = crossIndexArray(extfacepcellpfacetbl, cellpcelltbl, {'pcells'});

            map = TensorMap();
            map.fromTbl  = pcellpfacetbl;
            map.toTbl    = cellextfacepcellpfacetbl;
            map.mergefds = {'pcells', 'pfaces'};
            
            extfaces.faces              = cellextfacepcellpfacetbl.get('faces');
            extfaces.cells              = cellextfacepcellpfacetbl.get('cells');
            extfaces.halfTransParentInd = map.getDispatchInd();

            faceextfacemap = zeros(facetbl.num, 1);
            faceextfacemap(extfacetbl.get('faces')) = (1 : extfacetbl.num)';
            
            subG.helpers = struct('diffop'        , diffop  , ...
                                  'trans'         , trans   , ...
                                  'extfaces'      , extfaces, ...
                                  'faceextfacemap', faceextfacemap);
            
            
        end
        
        function vols = getVolumes(subG)

            pvols = subG.parentGrid.tPFVgeometry.cells.volumes;
            cmap  = subG.mappings.cellmap;
            
            vols = pvols(cmap);

        end

        function v = getGrad(subG, c)

            v = subG.helpers.diffop.grad*c;
            
        end

        function u = getDiv(subG, v)

            u = subG.helpers.diffop.div*v;
            
        end

        function grid = setupCellFluxOperators(grid)

            G = getMRSTgrid(grid);
            grid.cellFluxOperators = getCellFluxOperatorsAll(G);
            
        end

        function u = getFlux(subG, c)
        % Returns fluxes for each internal faces for the cell-valued vector c

            op = subG.helpers.trans;
            hT = subG.parentGrid.tPFVgeometry.hT;
            
            u = 1 ./ (op.S * ( 1 ./ (op.D*c .* op.P*hT)));
            
        end

        function [bchT, bccells] = getBcFlux(subG, u, bcfaces)
        % Returns half transmissibilities and cell indexing for the given boundary faces (bcfaces is given using subgrid indexing)

            hT   = subG.parentGrid.tPFVgeometry.hT;
            exf  = subG.helpers.extfaces;

            extfaceind = subG.helpers.faceextfacemap(bcfaces);
            
            bccells = exf.cells(extfaceind);
            bchT    = hT(exf.halfTransParentInd(extfaceind));
            
        end

        function jsq = getCellFluxNorm(subG, u)
    
            P = subG.cellFluxOperators.P;
            S = subG.cellFluxOperators.S;
    
            j = P*u;
            jsq = j.^2;
            jsq = S*jsq;
            
        end
        
    end
    
end
