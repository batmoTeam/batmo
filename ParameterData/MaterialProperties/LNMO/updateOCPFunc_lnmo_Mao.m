function [OCP, dUdT] = updateOCPFunc_lnmo(c, T, cmax)
    
    Tref = 293.15;  % [K]

    theta = c./cmax;
    
    refOCP_table = [[ 0e-2 , 4.7336]; ...
                   [10e-2 , 4.7309]; ...
                   [20e-2 , 4.7251]; ...
                   [30e-2 , 4.7248]; ...
                   [40e-2 , 4.7184]; ...
                   [50e-2 , 4.6806]; ...
                   [60e-2 , 4.6742]; ...
                   [70e-2 , 4.6681]; ...
                   [80e-2 , 4.6589]; ...
                   [85e-2 , 4.4763]; ...
                   [90e-2 , 4.1264]; ...
                   [100e-2, 3.7273]];

    refOCP = interpTable(refOCP_table(:, 1), refOCP_table(:, 2), theta);
    
    dUdT_table = [[0e-2  ,  -0.06e-3]; ...
                 [10e-2 , -0.061e-3]; ...
                 [20e-2 , -0.095e-3]; ...
                 [30e-2 , -0.123e-3]; ...
                 [40e-2 , -0.324e-3]; ...
                 [50e-2 , -0.178e-3]; ...
                 [60e-2 , -0.168e-3]; ...
                 [70e-2 , -0.191e-3]; ...
                 [80e-2 , -0.249e-3]; ...
                 [85e-2 , -2.788e-3]; ...
                 [90e-2 , -1.297e-3]; ...
                 [100e-2, -0.954e-3]];
    
    dUdT = interpTable(dUdT_table(:, 1), dUdT_table(:, 2), theta);    
    
    % Calculate the open-circuit potential of the active material
   
    OCP = refOCP + (T - Tref).*dUdT;
    
end


























