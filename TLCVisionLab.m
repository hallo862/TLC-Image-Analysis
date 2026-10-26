function TLCVisionLab
% TLCVISIONLAB - Interactive TLC image analysis and Rf measurement tool.
% Save as TLCVisionLab.m and run by typing TLCVisionLab in MATLAB.
%
% Features:
%   - Load a TLC photograph
%   - Click to mark baseline and solvent front
%   - Detect candidate spots using image thresholding
%   - Review/edit detections by clicking spot centers manually
%   - Calculate Rf values and export results to CSV
%
% Best results: use a sharp, well-lit image with the TLC plate filling most
% of the frame. Detection is a candidate-finding aid, not a substitute for
% checking the marked spots. Image Processing Toolbox is recommended.

    app.img = [];
    app.rgb = [];
    app.gray = [];
    app.baseY = NaN;
    app.frontY = NaN;
    app.spots = zeros(0,2); % [x y] image pixel coordinates
    app.spotRows = table();
    app.clickMode = "";
    app.darkSpots = true;
    app.threshold = 0.12;
    app.minArea = 8;
    app.maxArea = 2500;

    app.fig = figure('Name','TLC Vision Lab','NumberTitle','off', ...
        'Color',[0.96 0.97 0.98],'MenuBar','none','ToolBar','figure', ...
        'Units','normalized','Position',[0.08 0.08 0.84 0.82], ...
        'WindowButtonDownFcn',@onFigureClick);

    app.ax = axes('Parent',app.fig,'Units','normalized', ...
        'Position',[0.06 0.16 0.66 0.78]);
    axis(app.ax,'off');
    title(app.ax,'Load a TLC image to begin','FontSize',14);

    panel = uipanel('Parent',app.fig,'Title','TLC analysis', ...
        'FontSize',12,'Units','normalized','Position',[0.75 0.12 0.22 0.83], ...
        'BackgroundColor',[0.96 0.97 0.98]);

    y = 0.91; h = 0.055; gap = 0.018;
    addButton('Load image',@loadImage);
    addButton('Mark baseline',@markBaseline);
    addButton('Mark solvent front',@markFront);
    addButton('Detect spots',@detectSpots);
    addButton('Add / edit spots',@editSpots);
    addButton('Calculate Rf',@calculateRf);
    addButton('Export CSV',@exportCsv);

    uicontrol(panel,'Style','text','Units','normalized', ...
        'Position',[0.06 0.40 0.88 0.055],'String','Spot polarity', ...
        'HorizontalAlignment','left','BackgroundColor',get(panel,'BackgroundColor'), ...
        'FontWeight','bold');
    app.polarity = uicontrol(panel,'Style','popupmenu','Units','normalized', ...
        'Position',[0.06 0.355 0.88 0.05], ...
        'String',{'Dark spots on light background','Bright spots on dark background'}, ...
        'Value',1,'Callback',@polarityChanged);

    uicontrol(panel,'Style','text','Units','normalized', ...
        'Position',[0.06 0.29 0.88 0.055],'String','Detection sensitivity', ...
        'HorizontalAlignment','left','BackgroundColor',get(panel,'BackgroundColor'), ...
        'FontWeight','bold');
    app.sens = uicontrol(panel,'Style','slider','Units','normalized', ...
        'Position',[0.06 0.265 0.88 0.035],'Min',0.03,'Max',0.35,'Value',app.threshold, ...
        'Callback',@sensitivityChanged);
    app.sensLabel = uicontrol(panel,'Style','text','Units','normalized', ...
        'Position',[0.06 0.225 0.88 0.035],'String','0.12', ...
        'HorizontalAlignment','left','BackgroundColor',get(panel,'BackgroundColor'));

    app.status = uicontrol(panel,'Style','text','Units','normalized', ...
        'Position',[0.06 0.04 0.88 0.16], ...
        'String',{'Ready.','1. Load an image','2. Mark baseline/front','3. Detect spots'}, ...
        'HorizontalAlignment','left','BackgroundColor',get(panel,'BackgroundColor'));

    function addButton(label,callback)
        uicontrol(panel,'Style','pushbutton','Units','normalized', ...
            'Position',[0.06 y 0.88 h],'String',label,'FontSize',10, ...
            'Callback',callback);
        y = y - h - gap;
    end

    function setStatus(varargin)
        app.status.String = varargin;
        drawnow;
    end

    function loadImage(~,~)
        [f,pth] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.tiff;*.bmp','Image files'}, ...
            'Select TLC plate photograph');
        if isequal(f,0), return; end
        try
            raw = imread(fullfile(pth,f));
            if ndims(raw)==2
                app.img = raw;
                app.rgb = repmat(raw,1,1,3);
            else
                app.img = raw;
                app.rgb = raw(:,:,1:min(3,size(raw,3)));
                if size(app.rgb,3)==1, app.rgb=repmat(app.rgb,1,1,3); end
            end
            app.gray = toGrayDouble(app.img);
            app.baseY = NaN;
            app.frontY = NaN;
            app.spots = zeros(0,2);
            app.spotRows = table();
            showImage();
            setStatus('Image loaded.',f,'Mark baseline and solvent front.');
        catch ME
            errordlg(ME.message,'Could not load image');
        end
    end

    function markBaseline(~,~)
        if isempty(app.img), errordlg('Load an image first.'); return; end
        app.clickMode = "baseline";
        setStatus('Click the baseline on the image.');
    end

    function markFront(~,~)
        if isempty(app.img), errordlg('Load an image first.'); return; end
        app.clickMode = "front";
        setStatus('Click the solvent front on the image.');
    end

    function editSpots(~,~)
        if isempty(app.img), errordlg('Load an image first.'); return; end
        choice = questdlg('Add spots by clicking, or clear all current detections first?', ...
            'Edit spots','Add clicks','Clear and add','Cancel','Add clicks');
        if strcmp(choice,'Cancel') || isempty(choice), return; end
        if strcmp(choice,'Clear and add'), app.spots=zeros(0,2); end
        app.clickMode = "spots";
        setStatus('Click each spot center. Press Enter in the figure to finish.');
        figure(app.fig);
        try
            [x,y] = ginput;
            if ~isempty(x)
                app.spots = [app.spots; [x(:),y(:)]];
                app.spots = unique(round(app.spots,1),'rows','stable');
            end
        catch
        end
        app.clickMode = "";
        showImage();
        setStatus(sprintf('%d spot center(s) recorded.',size(app.spots,1)), ...
            'Click Calculate Rf to update the table.');
    end

    function detectSpots(~,~)
        if isempty(app.img), errordlg('Load an image first.'); return; end
        if ~isfinite(app.baseY) || ~isfinite(app.frontY)
            errordlg('Mark the baseline and solvent front first.'); return;
        end
        try
            I = app.gray;
            % Remove slow illumination changes using a broad local background.
            % imgaussfilt and imbinarize require Image Processing Toolbox.
            if exist('imgaussfilt','file')==2
                background = imgaussfilt(I, max(8,round(min(size(I))/35)));
                if app.darkSpots
                    contrast = background - I;
                else
                    contrast = I - background;
                end
            else
                errordlg(['Image Processing Toolbox is required for automatic ', ...
                    'spot detection. Use Add / edit spots instead.'],'Toolbox required');
                return;
            end
            contrast = mat2gray(contrast);
            mask = contrast > app.threshold;
            % Restrict analysis to the area between baseline and solvent front.
            lo = max(1,round(min(app.baseY,app.frontY)));
            hi = min(size(mask,1),round(max(app.baseY,app.frontY)));
            keep = false(size(mask));
            keep(lo:hi,:) = true;
            mask = mask & keep;

            % Remove tiny noise and connect fragmented spot pixels lightly.
            mask = bwareaopen(mask,app.minArea);
            mask = imclose(mask,strel('disk',2,0));
            cc = bwconncomp(mask);
            props = regionprops(cc,'Area','Centroid','BoundingBox','Eccentricity');
            candidates = zeros(0,2);
            for ii=1:numel(props)
                a = props(ii).Area;
                bb = props(ii).BoundingBox;
                aspect = bb(3)/max(bb(4),eps);
                if a >= app.minArea && a <= app.maxArea && ...
                        bb(3) < size(I,2)*0.35 && bb(4) < size(I,1)*0.25 && ...
                        aspect > 0.15 && aspect < 6
                    candidates(end+1,:) = props(ii).Centroid; %#ok<AGROW>
                end
            end
            if isempty(candidates)
                setStatus('No spots detected.', ...
                    'Try adjusting sensitivity or use Add / edit spots.');
            else
                app.spots = candidates;
                showImage();
                setStatus(sprintf('Detected %d candidate spot(s).',size(app.spots,1)), ...
                    'Review detections; add or clear spots if needed.', ...
                    'Then click Calculate Rf.');
            end
        catch ME
            errordlg(sprintf('Spot detection failed:\n%s',ME.message),'Detection error');
        end
    end

    function calculateRf(~,~)
        if isempty(app.img), errordlg('Load an image first.'); return; end
        if ~isfinite(app.baseY) || ~isfinite(app.frontY)
            errordlg('Mark baseline and solvent front first.'); return;
        end
        if isempty(app.spots)
            errordlg('Detect spots or add spot centers first.'); return;
        end
        totalDistance = abs(app.frontY-app.baseY);
        if totalDistance < 1
            errordlg('Baseline and solvent front must be distinct.'); return;
        end
        d = abs(app.spots(:,2)-app.baseY);
        rf = d./totalDistance;
        within = d <= totalDistance;
        n = size(app.spots,1);
        app.spotRows = table((1:n)',app.spots(:,1),app.spots(:,2),d,rf,within, ...
            'VariableNames',{'Spot','X_pixel','Y_pixel','Distance_pixels','Rf','WithinSolventFront'});
        showImage();
        disp(app.spotRows);
        setStatus(sprintf('Calculated %d Rf value(s).',n), ...
            sprintf('Mean Rf: %.3f',mean(rf(within),'omitnan')), ...
            'Export CSV to save the measurements.');
    end

    function exportCsv(~,~)
        if isempty(app.spotRows) || height(app.spotRows)==0
            calculateRf();
            if isempty(app.spotRows) || height(app.spotRows)==0, return; end
        end
        [f,pth] = uiputfile('TLC_Results.csv','Export TLC measurements');
        if isequal(f,0), return; end
        try
            writetable(app.spotRows,fullfile(pth,f));
            setStatus('CSV exported:',fullfile(pth,f));
        catch ME
            errordlg(ME.message,'Export failed');
        end
    end

    function polarityChanged(src,~)
        app.darkSpots = (src.Value==1);
    end

    function sensitivityChanged(src,~)
        app.threshold = src.Value;
        app.sensLabel.String = sprintf('%.2f',app.threshold);
    end

    function onFigureClick(~,~)
        if isempty(app.img) || app.clickMode=="", return; end
        cp = get(app.ax,'CurrentPoint');
        x = cp(1,1); ypix = cp(1,2);
        if x < 1 || ypix < 1 || x > size(app.img,2) || ypix > size(app.img,1)
            return;
        end
        switch app.clickMode
            case "baseline"
                app.baseY = ypix;
                app.clickMode = "";
                showImage();
                setStatus(sprintf('Baseline marked at row %.1f.',app.baseY), ...
                    'Now click Mark solvent front.');
            case "front"
                app.frontY = ypix;
                app.clickMode = "";
                showImage();
                setStatus(sprintf('Solvent front marked at row %.1f.',app.frontY), ...
                    'Click Detect spots or Add / edit spots.');
        end
    end

    function showImage()
        if isempty(app.img), return; end
        cla(app.ax);
        imshow(app.img,'Parent',app.ax);
        hold(app.ax,'on');
        if isfinite(app.baseY)
            yline(app.ax,app.baseY,'g-','Baseline','LineWidth',1.5, ...
                'LabelHorizontalAlignment','left');
        end
        if isfinite(app.frontY)
            yline(app.ax,app.frontY,'r-','Solvent front','LineWidth',1.5, ...
                'LabelHorizontalAlignment','left');
        end
        if ~isempty(app.spots)
            plot(app.ax,app.spots(:,1),app.spots(:,2),'yo', ...
                'MarkerSize',9,'LineWidth',1.5);
            for jj=1:size(app.spots,1)
                text(app.ax,app.spots(jj,1),app.spots(jj,2),sprintf(' %d',jj), ...
                    'Color','yellow','FontWeight','bold','FontSize',10, ...
                    'VerticalAlignment','bottom');
            end
        end
        hold(app.ax,'off');
        title(app.ax,'TLC Vision Lab — review all marked features');
    end
end

function I = toGrayDouble(img)
% Convert grayscale or RGB image to normalized grayscale double.
    if isfloat(img)
        A = double(img);
        if max(A(:)) > 1, A = A/255; end
    else
        A = im2double(img);
    end
    if ndims(A)==3 && size(A,3)>=3
        I = 0.2989*A(:,:,1) + 0.5870*A(:,:,2) + 0.1140*A(:,:,3);
    else
        I = A(:,:,1);
    end
    I = min(max(I,0),1);
end
