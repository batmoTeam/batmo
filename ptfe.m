classdef ptfe
    %UNTITLED9 Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        
        % Physical constants
        con = physicalConstants();
        
        % State properties
        eps     % Volume fraction,  [-]
        
    end
    
    methods
        function obj = ptfe()
            %UNTITLED9 Construct an instance of this class
            %   Detailed explanation goes here
            obj.eps = 0.03;
        end

    end
end

