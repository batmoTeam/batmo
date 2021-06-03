G = model.G;

ne    = 'NegativeElectrode';
pe    = 'PositiveElectrode';
eac   = 'ElectrodeActiveComponent';
cc    = 'CurrentCollector';
elyte = 'Electrolyte';
sep   = 'Separator';
thermal = 'ThermalModel';

h = figure(); 
set(h, 'Position', [10 10 1700 500]);

dovideo = false;

if dovideo
    filename = 'concentration.avi';
    video = VideoWriter(filename);
    video.FrameRate = 3;
    open(video);
end


for ind = 1 : numel(states)
    
    state = states{ind};
    
    figure(h);
    
    subplot(2, 2, 1);
    plotCellData(model.(elyte).G, state.(elyte).cs{1});
    colorbar
    view([30, 32]);
    title('cLi (elyte)');
    
    subplot(2, 2, 2);
    plotCellData(model.(ne).(eac).G, state.(ne).(eac).c);
    colorbar
    view([30, 32]);
    title('cLi (negative elde)');
    
    subplot(2, 2, 3);
    plotCellData(model.(pe).(eac).G, state.(pe).(eac).c);
    colorbar
    view([30, 32]);
    title('cLi (positive elde)');
    
    subplot(2, 2, 4);
    plot((time(1 : ind)/hour), Enew(1 : ind), '*-');
    xlabel('hours');
    ylabel('E');
    axis([0, max(time)/hour, min(Enew), max(Enew)])
    
    if dovideo
        frame = getframe(gcf);
        writeVideo(video, frame);
    end
    
    pause(0.1);
    
end

if dovideo
    close(video);
end

