function fn = setupFunction(jsonstruct)

    switch jsonstruct.functionFormat
        
      case 'tabulated'

        switch jsonstruct.numberOfArguments

          case 1
            
            fn = TabulatedFunction1D(jsonstruct);
            
          case 2
            
            error('bilinear interpolate function not supported yet');
            
          otherwise
            
            error('the given number of arguments is not supported');
            
        end
        
      case 'string expression'

        fn = StringExpFunction(jsonstruct);
        
      case 'named function'
        
        fn = NamedFunction(jsonstruct);
        
      case 'constant'

        fn = ConstantFunction(jsonstruct);

      otherwise

        error('function format not recognized');
        
    end
        
end
