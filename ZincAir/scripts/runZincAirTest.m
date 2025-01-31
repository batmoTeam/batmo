jsonstruct = parseBattmoJson('ZincAir/json_inputs/zincair_battery.json');

inputparams = ZincAirBatteryInputParams(jsonstruct);

elyte = 'Electrolyte';
ct    = 'Cathode';
ctam  = 'CathodeActiveMaterial';
an    = 'Anode';
anam  = 'AnodeActiveMaterial';

%% Setup geometry

gen = SeaWaterBatteryGeneratorP2D();
% We increase the resolution
gen.fac = 20;
gen = gen.applyResolutionFactors();

inputparams = gen.updateBatteryInputParams(inputparams);

%% Setup model

model = ZincAirBattery(inputparams);

cgt = model.cgt;
cgp = model.cgp;
