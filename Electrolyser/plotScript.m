time = cellfun(@(state) state.time, states);
E = cellfun(@(state) state.(oer).(ptl).E, states);
I = cellfun(@(state) state.(oer).(ctl).I, states);

close all

figure
plot(time/hour, E)
xlabel('time [hour]');
ylabel('voltage');

figure
plot(time/hour, I)
xlabel('time [hour]');
ylabel('Current [A]');

figure
plot(-I(end : - 1 : 1), E(end : - 1 : 1))
xlabel('Current [A]');
ylabel('Voltage [V]');
