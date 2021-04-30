function cons = assembleConservationEquation(model, flux, bcflux, source, accum)
    
    if nargin < 5
        accum = 0;
    end
        
    op = model.operators;
    
    % cons = accum + (op.Div(flux) - bcflux) - source;
    cons = op.AccDiv(accum,flux);
    cons = cons - bcflux - source;
    
end
