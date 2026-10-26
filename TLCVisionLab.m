function TLCVisionLab
% TLC Vision Lab
% This program lets you load a TLC image, mark the baseline and solvent
% front, record spots, calculate Rf values, and save the results.

    img = [];
    baseY = NaN;
    frontY = NaN;
    spots = [];
    results = table();

    % Create the main window
    fig = figure('Name','TLC Vision Lab', ...
        'NumberTitle','off','Position',[100 100 1000 650]);

    ax = axes('Parent',fig,'Position',[0.06 0.18 0.62 0.75]);
    axis(ax,'off');

    % Buttons
    uicontrol(fig,'Style','pushbutton','String','Load Image', ...
        'Units','normalized','Position',[0.74 0.82 0.20 0.07], ...
        'Callback',@loadImage);

    uicontrol(fig,'Style','pushbutton','String','Mark Baseline', ...
        'Units','normalized','Position',[0.74 0.72 0.20 0.07], ...
        'Callback',@markBaseline);

    uicontrol(fig,'Style','pushbutton','String','Mark Solvent Front', ...
        'Units','normalized','Position',[0.74 0.62 0.20 0.07], ...
        'Callback',@markFront);

    uicontrol(fig,'Style','pushbutton','String','Add Spots', ...
        'Units','normalized','Position',[0.74 0.52 0.20 0.07], ...
        'Callback',@addSpots);

    uicontrol(fig,'Style','pushbutton','String','Calculate Rf', ...
        'Units','normalized','Position',[0.74 0.42 0.20 0.07], ...
        'Callback',@calculateRf);

    uicontrol(fig,'Style','pushbutton','String','Export CSV', ...
        'Units','normalized','Position',[0.74 0.32 0.20 0.07], ...
        'Callback',@exportResults);

    status = uicontrol(fig,'Style','text', ...
        'Units','normalized','Position',[0.06 0.03 0.88 0.10], ...
        'String','Load a TLC image to get started.', ...
        'HorizontalAlignment','left','FontSize',11);

    % Load an image
    function loadImage(~,~)
        [file,path] = uigetfile( ...
            {'*.jpg;*.png;*.tif;*.bmp','Image files'});

        if isequal(file,0)
            return
        end

        img = imread(fullfile(path,file));
        baseY = NaN;
        frontY = NaN;
        spots = [];
        results = table();

        redraw();
        status.String = 'Image loaded. Mark the baseline first.';
    end

    % Mark the baseline
    function markBaseline(~,~)
        if isempty(img)
            status.String = 'Load an image first.';
            return
        end

        axes(ax);
        title(ax,'Click on the baseline');
        [~,y] = ginput(1);

        if isempty(y)
            return
        end

        baseY = y;
        redraw();
        status.String = 'Baseline marked. Mark the solvent front.';
    end

    % Mark the solvent front
    function markFront(~,~)
        if isempty(img)
            status.String = 'Load an image first.';
            return
        end

        axes(ax);
        title(ax,'Click on the solvent front');
        [~,y] = ginput(1);

        if isempty(y)
            return
        end

        frontY = y;
        redraw();
        status.String = 'Solvent front marked. Add the spot centers.';
    end

    % Add spots manually
    function addSpots(~,~)
        if isempty(img)
            status.String = 'Load an image first.';
            return
        end

        axes(ax);
        title(ax,'Click each spot center. Press Enter when finished.');

        [x,y] = ginput;

        if ~isempty(x)
            spots = [spots; x(:),y(:)];
        end

        redraw();
        status.String = sprintf('%d spots recorded.',size(spots,1));
    end

    % Calculate Rf values
    function calculateRf(~,~)
        if isempty(img) || isempty(spots)
            status.String = 'Load an image and add at least one spot.';
            return
        end

        if ~isfinite(baseY) || ~isfinite(frontY)
            status.String = 'Mark both the baseline and solvent front.';
            return
        end

        solventDistance = abs(frontY-baseY);

        if solventDistance == 0
            status.String = 'The baseline and solvent front must differ.';
            return
        end

        spotDistance = abs(spots(:,2)-baseY);
        rf = spotDistance/solventDistance;

        % Flag spots outside the baseline-to-front distance
        withinFront = spotDistance <= solventDistance;

        results = table((1:size(spots,1))',spots(:,1),spots(:,2), ...
            spotDistance,rf,withinFront, ...
            'VariableNames',{'Spot','X_pixel','Y_pixel', ...
            'Distance_pixels','Rf','WithinSolventFront'});

        disp(results);
        redraw();

        status.String = sprintf( ...
            'Calculated %d Rf values. Results are shown in the Command Window.', ...
            height(results));
    end

    % Save results to a CSV file
    function exportResults(~,~)
        if isempty(results)
            status.String = 'Calculate Rf values before exporting.';
            return
        end

        [file,path] = uiputfile('TLC_Results.csv');

        if isequal(file,0)
            return
        end

        writetable(results,fullfile(path,file));
        status.String = 'Results exported successfully.';
    end

    % Display the image and marked features
    function redraw()
        if isempty(img)
            return
        end

        cla(ax);
        imshow(img,'Parent',ax);
        hold(ax,'on');

        if isfinite(baseY)
            yline(ax,baseY,'g-','Baseline');
        end

        if isfinite(frontY)
            yline(ax,frontY,'r-','Solvent Front');
        end

        if ~isempty(spots)
            plot(ax,spots(:,1),spots(:,2),'yo', ...
                'MarkerSize',9,'LineWidth',1.5);
        end

        hold(ax,'off');
        title(ax,'TLC Plate');
    end
end