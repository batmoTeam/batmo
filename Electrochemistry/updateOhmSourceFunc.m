function  state = updateOhmSourceFunc(model, state)

    op = model.operators.cellFluxOp;
    R = model.ohmicResistance;
    vols = G.cells.volumes;
    
    j = state.j;
    j = op.P*j;
    jsq = j.^2;
    jsq = op.S*jsq;
    
    state.jHeatOhmSource = vols.*jsq./R;
    
end