function output = spiralGrid(params)
    
    %% Parameters 
    % 
    % params structure with following fields
    % - nwindings : number of windings in the spiral
    % - r0        : "radius" at the middle
    % - widths    : vector of widths for each component indexed in following order (see tagdict below in code)
    %                 - positive current collector
    %                 - positive active material
    %                 - electrolyte separator 
    %                 - negative active material
    %                 - negative current collector
    % - L         : length of the battery
    % - nrs       : number of cell in radial direction for each component (same ordering as above).
    % - nas       : number of cells in the angular direction
    % - nL        : number of discretization cells in the longitudonal
    %
    % RETURNS
    %
    % - G       : grid
    % - tag     : cell-valued vector giving component number (indexing is given by tagdict)
    % - tagdict : dictionary giving the component number
    
    nwindings = params.nwindings;
    r0        = params.r0     ;
    widths    = params.widths ;
    nrs       = params.nrs    ;
    nas       = params.nas    ;
    L         = params.L      ;
    nL        = params.nL;

    %% component names
    compnames = {'PositiveCurrentCollector', ...
                 'PositiveActiveMaterial'  , ...
                 'ElectrolyteSeparator'    , ...
                 'NegativeActiveMaterial'  , ...
                 'NegativeCurrentCollector'};
    
    comptag = (1 : numel(compnames));
    tagdict = containers.Map(compnames, comptag);

    
    %% Grid setup

    layerwidth = sum(widths);

    w = widths./nrs;
    w = rldecode(w, nrs);

    w = repmat(w, [nwindings, 1]);
    w = [0; cumsum(w)];

    h = linspace(0, 2*pi*r0, nas*nwindings + 1);

    nperlayer = sum(nrs);

    cartG = tensorGrid(h, w);

    n = numel(h) - 1;
    m = numel(w) - 1;

    % plotGrid(cartG)

    % We roll the domain into a spirale
    x = cartG.nodes.coords(:, 1);
    y = cartG.nodes.coords(:, 2);

    theta = x./r0;

    cartG.nodes.coords(:, 1) = (r0 + y + (theta/(2*pi))*layerwidth).*cos(theta);
    cartG.nodes.coords(:, 2) = (r0 + y + (theta/(2*pi))*layerwidth).*sin(theta);

    tbls = setupSimpleTables(cartG);

    % We add cartesian indexing for the nodes
    nodetbl.nodes = (1 : cartG.nodes.num)';
    nodetbl.indi = repmat((1 : (n + 1))', m + 1, 1);
    nodetbl.indj = rldecode((1 : (m + 1))', (n + 1)*ones(m + 1, 1));
    nodetbl = IndexArray(nodetbl);

    % We add cartesian indexing for the vertical faces (in original cartesian block)
    vertfacetbl.faces = (1 : (n + 1)*m)';
    vertfacetbl.indi = repmat((1 : (n + 1))', m, 1);
    vertfacetbl.indj = rldecode((1 : m)', (n + 1)*ones(m, 1));
    vertfacetbl = IndexArray(vertfacetbl);

    % Add structure to merge the nodes
    node2tbl.indi1 = ones(m - nperlayer + 1, 1);
    node2tbl.indj1 = ((nperlayer + 1) : (m + 1))';
    node2tbl.indi2 = (n + 1)*ones(m - nperlayer + 1, 1);
    node2tbl.indj2 = (1 : (m - nperlayer + 1))';
    node2tbl = IndexArray(node2tbl);

    gen = CrossIndexArrayGenerator();
    gen.tbl1 = nodetbl;
    gen.tbl2 = node2tbl;
    gen.replacefds1 = {{'indi', 'indi1'}, {'indj', 'indj1'}, {'nodes', 'nodes1'}};
    gen.mergefds = {'indi1', 'indj1'};

    node2tbl = gen.eval();

    gen = CrossIndexArrayGenerator();
    gen.tbl1 = nodetbl;
    gen.tbl2 = node2tbl;
    gen.replacefds1 = {{'indi', 'indi2'}, {'indj', 'indj2'}, {'nodes', 'nodes2'}};
    gen.mergefds = {'indi2', 'indj2'};

    node2tbl = gen.eval();

    node2tbl = sortIndexArray(node2tbl, {'nodes1', 'nodes2'});

    % Add structure to merge the faces
    face2tbl.indi1 = ones(m - nperlayer, 1);
    face2tbl.indj1 = nperlayer + (1 : (m - nperlayer))';
    face2tbl.indi2 = (n + 1)*ones(m - nperlayer, 1);
    face2tbl.indj2 = (1 : (m - nperlayer))';
    face2tbl = IndexArray(face2tbl);

    gen = CrossIndexArrayGenerator();
    gen.tbl1 = vertfacetbl;
    gen.tbl2 = face2tbl;
    gen.replacefds1 = {{'indi', 'indi1'}, {'indj', 'indj1'}, {'faces', 'faces1'}};
    gen.mergefds = {'indi1', 'indj1'};

    face2tbl = gen.eval();

    gen = CrossIndexArrayGenerator();
    gen.tbl1 = vertfacetbl;
    gen.tbl2 = face2tbl;
    gen.replacefds1 = {{'indi', 'indi2'}, {'indj', 'indj2'}, {'faces', 'faces2'}};
    gen.mergefds = {'indi2', 'indj2'};

    face2tbl = gen.eval();


    %% We setup the new indexing for the nodes

    nodetoremove = node2tbl.get('nodes2');
    newnodes = (1 : cartG.nodes.num)';
    newnodes(nodetoremove) = [];

    newnodetbl.newnodes = (1 : numel(newnodes))';
    newnodetbl.nodes = newnodes;
    newnodetbl = IndexArray(newnodetbl);

    gen = CrossIndexArrayGenerator();
    gen.tbl1 = node2tbl;
    gen.tbl2 = newnodetbl;
    gen.replacefds2 = {{'nodes', 'nodes1'}};
    gen.mergefds = {'nodes1'};

    node2tbl = gen.eval();

    newnodes = [newnodetbl.get('newnodes'); node2tbl.get('newnodes')];
    nodes = [newnodetbl.get('nodes'); node2tbl.get('nodes2')];

    clear newnodetbl;
    newnodetbl.newnodes = newnodes;
    newnodetbl.nodes = nodes;
    newnodetbl = IndexArray(newnodetbl);

    %% We setup the new indexing for the faces

    facetoremove = face2tbl.get('faces2');
    newfaces = (1 : cartG.faces.num)';
    newfaces(facetoremove) = [];

    clear facetbl
    newfacetbl.newfaces = (1 : numel(newfaces))';
    newfacetbl.faces = newfaces;
    newfacetbl = IndexArray(newfacetbl);

    gen = CrossIndexArrayGenerator();
    gen.tbl1 = face2tbl;
    gen.tbl2 = newfacetbl;
    gen.replacefds2 = {{'faces', 'faces1'}};
    gen.mergefds = {'faces1'};

    face2tbl = gen.eval();

    newfaces = [newfacetbl.get('newfaces'); face2tbl.get('newfaces')];
    faces = [newfacetbl.get('faces'); face2tbl.get('faces2')];

    allnewfacetbl.newfaces = newfaces;
    allnewfacetbl.faces = faces;
    allnewfacetbl = IndexArray(allnewfacetbl);

    %% we maps from old to new

    cellfacetbl = tbls.cellfacetbl;
    % we store the order previous to mapping. Here we just assumed that the grid is cartesian for simplicity
    cellfacetbl = cellfacetbl.addInd('order', repmat((1 : 4)', cartG.cells.num, 1));

    cellfacetbl = crossIndexArray(cellfacetbl, allnewfacetbl, {'faces'});
    cellfacetbl = sortIndexArray(cellfacetbl, {'cells', 'order' 'newfaces'});
    cellfacetbl = replacefield(cellfacetbl, {{'newfaces', 'faces'}});

    facenodetbl = tbls.facenodetbl;
    % facenodetbl = facenodetbl.addInd('order', repmat((1 : 2)', cartG.faces.num, 1));
    facenodetbl = crossIndexArray(facenodetbl, newfacetbl, {'faces'});
    facenodetbl = crossIndexArray(facenodetbl, newnodetbl, {'nodes'});

    facenodetbl = sortIndexArray(facenodetbl, {'newfaces',  'newnodes'});
    facenodetbl = replacefield(facenodetbl, {{'newfaces', 'faces'}, {'newnodes', 'nodes'}});

    clear nodes
    nodes.coords = cartG.nodes.coords(newnodetbl.get('nodes'), :);
    nodes.num = size(nodes.coords, 1);

    clear faces
    [~, ind] = rlencode(facenodetbl.get('faces'));
    faces.nodePos = [1; 1 + cumsum(ind)];
    faces.nodes = facenodetbl.get('nodes');
    faces.num = newfacetbl.num;
    faces.neighbors = []; % to avoid warning in computeGeometry
    
    clear cells
    [~, ind] = rlencode(cellfacetbl.get('cells'));
    cells.facePos = [1; 1 + cumsum(ind)];
    cells.faces = cellfacetbl.get('faces');
    cells.num = cartG.cells.num;


    G.cells = cells;
    G.faces = faces;
    G.nodes = nodes;
    G.griddim = 2;
    G.type = {'spiralGrid'};
    G = computeGeometry(G, 'findNeighbors', true);

    % plotGrid(G)

    ncomp = numel(widths);
    comptag = rldecode((1 : ncomp)', nrs);
    comptag = repmat(comptag, [nwindings, 1]);

    comptagtbl.tag = comptag;
    comptagtbl.indj = (1 : (sum(nrs)*nwindings))';
    comptagtbl = IndexArray(comptagtbl);

    celltbl.cells = (1 : cartG.cells.num)';
    celltbl.indi = repmat((1 : nas*nwindings)', [sum(nrs)*nwindings, 1]);
    celltbl.indj = rldecode((1 : sum(nrs)*nwindings)', nas*nwindings*ones(sum(nrs)*nwindings, 1));
    celltbl = IndexArray(celltbl);

    celltagtbl = crossIndexArray(celltbl, comptagtbl, {'indj'});
    celltagtbl = sortIndexArray(celltagtbl, {'cells', 'tag'});

    tag = celltagtbl.get('tag');

    % Extrude battery in z-direction
    zwidths = (L/nL)*ones(nL, 1);
    G = makeLayeredGrid(G, zwidths);
    G = computeGeometry(G);
    
    tag = repmat(tag, [nL, 1]);

    % setup the standard tables
    tbls = setupSimpleTables(G);
    cellfacetbl = tbls.cellfacetbl;
    
    clear extfacetbl
    extfacetbl.faces = find(any(G.faces.neighbors == 0, 2));
    extfacetbl = IndexArray(extfacetbl);
    extcellfacetbl = crossIndexArray(extfacetbl, cellfacetbl, {'faces'});
    
    
    %%  recover the external faces that are inside the spiral
    % we get them using the Cartesian indexing


    [indi, indj, indk] = ind2sub([n, m, nL], (1 : G.cells.num)');
    
    clear celltbl
    celltbl.cells = (1 : G.cells.num)';
    celltbl.indi = indi;
    celltbl.indj = indj;
    celltbl.indk = indk;
    celltbl = IndexArray(celltbl);

    % We add vertical (1) and horizontal (2) direction index for the faces (see makeLayeredGrid for the setup)
    
    nf = G.faces.num;
    clear facetbl
    facetbl.faces = (1 : nf)';
    dir = 2*ones(nf, 1);
    dir(1 : (nL + 1)*n*m) = 1;
    facetbl.dir = dir;
    facetbl = IndexArray(facetbl);
    
    scelltbl.indi = (1: n)';
    scelltbl.indj = 1*ones(n, 1);
    scelltbl.dir = 2*ones(n, 1);
    scelltbl = IndexArray(scelltbl);
    
    scelltbl = crossIndexArray(celltbl, scelltbl, {'indi', 'indj'});
    scelltbl = projIndexArray(scelltbl, 'cells');
    extscellfacetbl = crossIndexArray(scelltbl, extcellfacetbl, {'cells'});
    sfacetbl = projIndexArray(extscellfacetbl, {'faces'});
    
    sfacetbl = sfacetbl.addInd('dir', 2*ones(sfacetbl.num, 1));
    sfacetbl = crossIndexArray(sfacetbl, facetbl, {'faces', 'dir'});
    
    sfaces = sfacetbl.get('faces');
    
    
    clear scelltbl
    nnrs = sum(nrs);
    scelltbl.indi = ones(nnrs, 1);
    scelltbl.indj = (1 : nnrs)';
    scelltbl = IndexArray(scelltbl);
    
    scelltbl = crossIndexArray(celltbl, scelltbl, {'indi', 'indj'});
    scelltbl = projIndexArray(scelltbl, 'cells');
    extscellfacetbl = crossIndexArray(scelltbl, extcellfacetbl, {'cells'});
    sfacetbl = projIndexArray(extscellfacetbl, {'faces'});
    
    sfacetbl = sfacetbl.addInd('dir', 2*ones(sfacetbl.num, 1));
    sfacetbl = crossIndexArray(sfacetbl, facetbl, {'faces', 'dir'});

    sfaces = [sfaces; sfacetbl.get('faces')];
    
    % some faces have been taken twice
    sfaces = unique(sfaces);

    clear sfacetbl
    sfacetbl.faces = sfaces;
    sfacetbl = IndexArray(sfacetbl);
    
    map = TensorMap();
    map.fromTbl = extfacetbl;
    map.toTbl = sfacetbl;
    map.mergefds = {'faces'};
    
    ind = map.getDispatchInd();
    
    thermalExchangeFaces = extfacetbl.get('faces');
    thermalExchangeFaces(ind) = [];
    
    
    %% recover faces on top and bottom for the current collector
    % we could do that using cartesian indices (easier)

    ccnames = {'PositiveCurrentCollector', 'NegativeCurrentCollector'};

    for ind = 1 : numel(ccnames)

        clear cccelltbl
        cccelltbl.cells = find(tag == tagdict(ccnames{ind}));
        cccelltbl = IndexArray(cccelltbl);

        extcccellfacetbl = crossIndexArray(extcellfacetbl, cccelltbl, {'cells'});
        extccfacetbl = projIndexArray(extcccellfacetbl, {'faces'});

        ccextfaces = extccfacetbl.get('faces');

        normals = G.faces.normals(ccextfaces, :);
        sgn = ones(numel(ccextfaces), 1);
        sgn(G.faces.neighbors(ccextfaces, 1) == 0) = -1;
        areas = G.faces.areas(ccextfaces, :);
        nnormals = sgn.*normals./areas;

        scalprod = bsxfun(@times, [0, 0, 1], nnormals);
        scalprod = sum(scalprod, 2);

        switch ccnames{ind}
          case 'PositiveCurrentCollector'
            ccfaces{ind} = ccextfaces(scalprod > 0.9);
          case 'NegativeCurrentCollector'
            ccfaces{ind} = ccextfaces(scalprod < -0.9);
          otherwise
            error('name not recognized');
        end
    end

    positiveExtCurrentFaces = ccfaces{1};
    negativeExtCurrentFaces = ccfaces{2};
    
    %% setup output structure
    output = params;
    output.G                       = G;
    output.tag                     = tag;
    output.tagdict                 = tagdict;
    output.positiveExtCurrentFaces = positiveExtCurrentFaces;
    output.negativeExtCurrentFaces = negativeExtCurrentFaces;
    output.thermalExchangeFaces    = thermalExchangeFaces;   
    
end