% InteractiveDataTipTool
%
% A utility class for interactively creating, managing, and aligning data tips
% on 2D line plots within a MATLAB axes. Users draw a line in the figure to
% create data tips at intersections with plotted lines (or at zero-crossings
% when constrained). The class also provides a companion Aligner UI for
% reviewing created data tips, snapping selected tips to target coordinates,
% exporting results to CSV or the MATLAB workspace, and restoring original
% curve positions.
%
% Key features:
% - Interactive creation of data tips by click-and-drag on an axes, with
%   support for constraint modes (free, horizontal, vertical, x-axis zero).
% - Snapping behavior that selects the nearest sample point on the intersected
%   line and optionally creates a datatip at that location.
% - Aligner app (uifigure) presenting a searchable table of data tips, a
%   movement log, and controls to: Refresh, Reset, Save (all/selected) to CSV,
%   Send (all/selected) to the MATLAB workspace, Snap selected signals to an
%   arbitrary X/Y, and show contextual help.
% - Movement history tracking with human-readable descriptions and a
%   UI-displayed movement log; ability to export MoveHistory to the base
%   workspace.
%
% Typical usage:
%   tool = InteractiveDataTipTool(ax);
%   tool.setEnabled(true);       % enable interactive data-tip creation
%   tool.openAligner();          % open the Aligner UI to manage tips
%
% Author: Ahmed Seleit
% Date:   2025-09-24


classdef InteractiveDataTipTool < handle
    properties
        Ax
        Fig
        Enable = false

        % draw-state
        PreviewLine = []
        IsDown = false
        StartPoint = [NaN NaN]
        ConstraintMode = 'free'

        % tips registry (snapped)
        % struct('hLine',h,'lineName',char,'idx',k,'x',double,'y',double,'hDT',handle)
        Tips = struct('hLine',{},'lineName',{},'idx',{},'x',{},'y',{},'hDT',{})

        % ---- Aligner (App UI) ----
        UIFig
        UITable            % main table
        MoveLogTextArea    % text area for logging all movements
        BtnSave
        BtnRefresh
        BtnToWS
        BtnReset
        BtnHelp
        BtnSnapTo
        BtnToWSSelected
        BtnSaveSelected
        BtnSelectAll

        % ---- Snap To Fields (embedded) ----
        SnapToXField
        SnapToYField

        % pending (first selection)
        PendingX = []      % struct('row',r,'hLine',h,'x',val)
        PendingY = []      % struct('row',r,'hLine',h,'y',val)

        % Move history list
        MoveHistory = struct('Time',{},'Signal',{},'Axis',{},'Delta',{},'Description',{})

        % original curve data for Reset
        OriginalLines = struct('hLine',{},'X',{},'Y',{})
        CachedOriginals = false

        % default CSV name
        DefaultCSVPath char
    end

    methods
        function obj = InteractiveDataTipTool(ax)
            obj.Ax  = ax;
            obj.Fig = ancestor(ax,'figure');
            obj.DefaultCSVPath = fullfile(pwd, ...
                sprintf('datatips_%s.csv', string(datetime('now','Format','yyyy-MM-dd_HHmmss'))));
        end

        function setEnabled(obj, tf)
            obj.Enable = logical(tf);
            if obj.Enable
                obj.cacheOriginalLines();   % grab originals once
                obj.Fig.Pointer               = 'crosshair';
                obj.Fig.WindowButtonDownFcn   = @(~,~)obj.mouseDown();
                obj.Fig.WindowButtonMotionFcn = @(~,~)obj.mouseMove();
                obj.Fig.WindowButtonUpFcn     = @(~,~)obj.mouseUp();
                obj.Fig.WindowKeyPressFcn     = @(~,evt)obj.keyPress(evt);
            else
                obj.Fig.Pointer               = 'arrow';
                obj.Fig.WindowButtonDownFcn   = [];
                obj.Fig.WindowButtonMotionFcn = [];
                obj.Fig.WindowButtonUpFcn     = [];
                obj.Fig.WindowKeyPressFcn     = [];
                obj.clearPreview();
            end
        end

        function openAligner(obj, varargin)
            % openAligner([x y w h]) or openAligner('Position',[...])
            pos = [120 100 1200 360];
            if ~isempty(varargin) && isnumeric(varargin{1}) && numel(varargin{1})==4
                pos = varargin{1}; varargin = varargin(2:end);
            end
            p = inputParser; addParameter(p,'Position',pos,@(v)isnumeric(v)&&numel(v)==4);
            parse(p,varargin{:}); pos = p.Results.Position;

            if isempty(obj.UIFig) || ~isgraphics(obj.UIFig)
                obj.UIFig = uifigure('Name','DataTip Aligner', 'Position', pos);
                % Keep child positions fixed when window is resized
                try obj.UIFig.AutoResizeChildren = 'off'; catch, end
                % Re-layout tables when window size changes
                try obj.UIFig.SizeChangedFcn = @(~,~)obj.onFigureResize(); catch, end
            else
                obj.UIFig.Position = pos; figure(obj.UIFig);
                try obj.UIFig.AutoResizeChildren = 'off'; catch, end
                try obj.UIFig.SizeChangedFcn = @(~,~)obj.onFigureResize(); catch, end
            end

            % Snap To section (above buttons)
            % Add Select All button to the left of the Snap label for a cleaner layout
            if isempty(obj.BtnSelectAll) || ~isgraphics(obj.BtnSelectAll)
                obj.BtnSelectAll = uibutton(obj.UIFig, ...
                    'Position', [10, 70, 100, 25], ...
                    'Text', 'Select All', ...
                    'ButtonPushedFcn', @(src,evt)obj.onSelectAllToggle());
            end

            % Snap UI moved below the Select All button for clearer flow
            uilabel(obj.UIFig, 'Text', 'Snap Selected To:', ...
                'Position', [10 52 130 20], 'FontWeight', 'bold');
            uilabel(obj.UIFig, 'Text', 'Target X:', ...
                'Position', [150 52 60 20]);
            if isempty(obj.SnapToXField) || ~isgraphics(obj.SnapToXField)
                obj.SnapToXField = uieditfield(obj.UIFig, 'numeric', ...
                    'Position', [210 52 80 22], 'Value', 0);
            end
            uilabel(obj.UIFig, 'Text', 'Target Y:', ...
                'Position', [310 52 60 20]);
            if isempty(obj.SnapToYField) || ~isgraphics(obj.SnapToYField)
                obj.SnapToYField = uieditfield(obj.UIFig, 'numeric', ...
                    'Position', [370 52 80 22], 'Value', 0);
            end
            if isempty(obj.BtnSnapTo) || ~isgraphics(obj.BtnSnapTo)
                obj.BtnSnapTo = uibutton(obj.UIFig,'Text','Snap Selected', ...
                    'Position',[460 50 100 26], ...
                    'BackgroundColor', [0.2 0.7 0.2], ...
                    'FontWeight', 'bold', ...
                    'ButtonPushedFcn', @(~,~)obj.onSnapToExecute());
            end

            % Removed vertical divider labels between button groups for a cleaner look

            % Section 1: Refresh and Reset buttons
            if isempty(obj.BtnRefresh) || ~isgraphics(obj.BtnRefresh)
                obj.BtnRefresh = uibutton(obj.UIFig,'Text','Refresh', ...
                    'Position',[16 12 75 30], ...
                    'Tooltip', 'Updates the table to remove deleted datatips', ...
                    'ButtonPushedFcn', @(~,~)obj.refreshTables());
            end
            if isempty(obj.BtnReset) || ~isgraphics(obj.BtnReset)
                obj.BtnReset = uibutton(obj.UIFig,'Text','Reset', ...
                    'Position',[95 12 75 30], ...
                    'Tooltip', 'Reset data tips to original positions', ...
                    'ButtonPushedFcn', @(~,~)obj.onResetCurves());
            end

            % Section 2: Save buttons
            if isempty(obj.BtnToWS) || ~isgraphics(obj.BtnToWS)
                obj.BtnToWS = uibutton(obj.UIFig,'Text','Send All to Workspace', ...
                    'Position',[180 12 140 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onSendToWorkspace());
            end
            if isempty(obj.BtnToWSSelected) || ~isgraphics(obj.BtnToWSSelected)
                obj.BtnToWSSelected = uibutton(obj.UIFig,'Text','Send Selected to Workspace', ...
                    'Position',[330 12 180 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onSendSelectedToWorkspace());
            end
            if isempty(obj.BtnSave) || ~isgraphics(obj.BtnSave)
                obj.BtnSave = uibutton(obj.UIFig,'Text','Save All to CSV', ...
                    'Position',[520 12 120 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onSaveCSV());
            end
            if isempty(obj.BtnSaveSelected) || ~isgraphics(obj.BtnSaveSelected)
                obj.BtnSaveSelected = uibutton(obj.UIFig,'Text','Save Selected to CSV', ...
                    'Position',[650 12 160 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onSaveSelectedCSV());
            end

            % Help button (rightmost)
            if isempty(obj.BtnHelp) || ~isgraphics(obj.BtnHelp)
                obj.BtnHelp = uibutton(obj.UIFig,'Text','Help', ...
                    'Position',[pos(3)-100 12 80 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onShowHelp());
            end

            % Compute initial layout metrics for table and text area
            try
                fpos = obj.UIFig.InnerPosition; % [x y w h]
            catch
                fpos = obj.UIFig.Position;
            end
            leftMargin   = 10; rightMargin = 10; bottomTables = 94; topMargin = 20;
            gapBetween   = 10;
            totalWidth = max(600, fpos(3) - leftMargin - rightMargin);
            tableWidth = floor(totalWidth * 0.6);  % 60% for table
            textWidth  = totalWidth - tableWidth - gapBetween;  % remainder for text area
            heightTbl  = max(120, fpos(4) - bottomTables - topMargin);

            % Main table: Select | Signal Name | X | Move X | Y | Move Y
            if isempty(obj.UITable) || ~isgraphics(obj.UITable)
                obj.UITable = uitable(obj.UIFig, ...
                    'Position',[leftMargin, bottomTables, tableWidth, heightTbl], ...
                    'RowName',[], ...
                    'ColumnName', {'Select','Signal Name','X','Move X','Y','Move Y'}, ...
                    'ColumnEditable', [true false false true false true], ...
                    'ColumnFormat', {'logical','char','numeric','logical','numeric','logical'}, ...
                    'ColumnSortable', [false true true false true false], ...
                    'ColumnWidth', {70, 150, 100, 80, 100, 80}, ...
                    'CellEditCallback', @(src,evt)obj.onUITableEdit(evt));
            end

            % Create Movement Log Text Area
            if isempty(obj.MoveLogTextArea) || ~isgraphics(obj.MoveLogTextArea)
                textX = leftMargin + tableWidth + gapBetween;
                obj.MoveLogTextArea = uitextarea(obj.UIFig, ...
                    'Position', [textX, bottomTables, textWidth, heightTbl], ...
                    'Editable', 'off', ...
                    'WordWrap', 'on', ...
                    'FontName', 'Monospace', ...
                    'FontSize', 12, ...
                    'Value', {'Movement Log:', '(No movements yet)'});
            end

            obj.refreshTables();
            % Initial layout pass to fit tables to current window
            obj.layoutTables();
        end

    end

    methods (Access=private)
        function onFigureResize(obj)
            % Delegate to shared layout to keep logic consistent
            obj.layoutTables();
        end

        function layoutTables(obj)
            % Recompute positions for both table and text area
            if isempty(obj.UIFig) || ~isgraphics(obj.UIFig), return; end
            % Use InnerPosition so calculations are in content coordinates
            try
                pos = obj.UIFig.InnerPosition; % [x y w h]
            catch
                pos = obj.UIFig.Position;
            end

            % Margins and sizes
            leftMargin   = 10;
            rightMargin  = 10;
            bottomTables = 94;    % keep clear of Snap row/buttons
            topMargin    = 20;    % small top padding
            gapBetween   = 10;    % gap between table and text area

            % Compute dimensions
            totalWidth = max(600, pos(3) - leftMargin - rightMargin);
            tableWidth = floor(totalWidth * 0.6);  % 60% for table
            textWidth  = totalWidth - tableWidth - gapBetween;  % remainder for text area
            heightTbl  = max(120, pos(4) - bottomTables - topMargin);

            % Apply positions if components exist
            if ~isempty(obj.UITable) && isgraphics(obj.UITable)
                obj.UITable.Position = [leftMargin, bottomTables, tableWidth, heightTbl];
            end

            if ~isempty(obj.MoveLogTextArea) && isgraphics(obj.MoveLogTextArea)
                textX = leftMargin + tableWidth + gapBetween;
                obj.MoveLogTextArea.Position = [textX, bottomTables, textWidth, heightTbl];
            end
        end
    end

    %% ===== Keyboard & mouse =====
    methods (Access=private)
        function keyPress(obj, evt)
            if isfield(evt,'Key') && strcmpi(evt.Key,'escape')
                if obj.IsDown
                    obj.clearPreview(); obj.IsDown=false; obj.ConstraintMode='free';
                end
            end
        end

        function mouseDown(obj)
            if ~obj.Enable || obj.isFigureModeActive(), return; end
            h = hittest(obj.Fig);
            if ~isempty(h) && (isa(h,'matlab.ui.container.Panel') || isa(h,'matlab.ui.control.UIControl'))
                return;
            end
            ax = ancestor(h,'axes'); if isempty(ax) || ax~=obj.Ax, return; end

            mods = get(obj.Fig,'CurrentModifier'); if ischar(mods), mods={mods}; end
            if any(contains(mods,{'control','command'}))
                obj.ConstraintMode = 'x-axis';
            else
                switch get(obj.Fig,'SelectionType')
                    case 'normal', obj.ConstraintMode='free';
                    case 'alt',    obj.ConstraintMode='horizontal';
                    case 'extend', obj.ConstraintMode='vertical';
                    otherwise,     obj.ConstraintMode='free';
                end
            end

            obj.IsDown = true; obj.StartPoint = obj.Ax.CurrentPoint(1,1:2);
            obj.clearPreview();
            obj.PreviewLine = line(obj.Ax,obj.StartPoint(1),obj.StartPoint(2), ...
                'Color','r','LineStyle','--','LineWidth',3,'Marker','o','MarkerSize',6, ...
                'HitTest','off','PickableParts','none');
        end

        function mouseMove(obj)
            if obj.isFigureModeActive(), return; end
            if ~obj.Enable || ~obj.IsDown || isempty(obj.PreviewLine), return; end
            p0=obj.StartPoint; p1=obj.Ax.CurrentPoint(1,1:2);
            switch obj.ConstraintMode
                case 'horizontal', p1(2)=p0(2);
                case 'vertical',   p1(1)=p0(1);
                case 'x-axis',     p1(2)=0;p0(2)=0;
            end
            set(obj.PreviewLine,'XData',[p0(1) p1(1)],'YData',[p0(2) p1(2)]);
            drawnow limitrate;
        end

        function mouseUp(obj)
            if ~obj.Enable || ~obj.IsDown, return; end
            if obj.isFigureModeActive()
                obj.clearPreview(); obj.IsDown=false; obj.ConstraintMode='free'; return;
            end
            p0=obj.StartPoint; p1=obj.Ax.CurrentPoint(1,1:2);
            switch obj.ConstraintMode
                case 'horizontal', p1(2)=p0(2);
                case 'vertical',   p1(1)=p0(1);
                case 'x-axis',     p0(2)=0;p1(2)=0;
            end
            obj.createDataTips(p0,p1);
            obj.clearPreview(); obj.IsDown=false; obj.ConstraintMode='free';
            if isgraphics(obj.UITable), obj.refreshTables(); end
        end
    end

    %% ===== Build tips =====
    methods (Access=private)
        function createDataTips(obj,p0,p1)
            L=findobj(obj.Ax,'Type','line');
            if strcmp(obj.ConstraintMode,'x-axis')
                xr=sort([p0(1) p1(1)]);
                for k=1:numel(L)
                    ln=L(k); if ~strcmp(get(ln,'Visible'),'on'), continue; end
                    X=get(ln,'XData'); Y=get(ln,'YData'); nm=obj.lineNameFor(ln,k);
                    for i=1:numel(X)-1
                        x1=X(i); y1=Y(i); x2=X(i+1); y2=Y(i+1);
                        if (y1<=0 && y2>=0) || (y1>=0 && y2<=0)
                            if y2~=y1
                                xC=x1+(0-y1)*(x2-x1)/(y2-y1);
                                if xC>=xr(1) && xC<=xr(2), obj.addSnappedTip(ln,[xC 0],nm); end
                            end
                        end
                    end
                end
            else
                for k=1:numel(L)
                    ln=L(k); if ~strcmp(get(ln,'Visible'),'on'), continue; end
                    X=get(ln,'XData'); Y=get(ln,'YData'); nm=obj.lineNameFor(ln,k);
                    for i=1:numel(X)-1
                        [hit,pt]=obj.lineIntersect(p0,p1,[X(i) Y(i)],[X(i+1) Y(i+1)]);
                        if hit, obj.addSnappedTip(ln,pt,nm); end
                    end
                end
            end
        end

        function addSnappedTip(obj,ln,pt,nm)
            X=get(ln,'XData'); Y=get(ln,'YData'); if isempty(X)||isempty(Y), return; end
            [~,idx]=min((X-pt(1)).^2+(Y-pt(2)).^2); xi=X(idx); yi=Y(idx);
            hdt=[]; try hdt=datatip(ln,xi,yi); catch, end 
            obj.Tips(end+1)=struct('hLine',ln,'lineName',nm,'idx',idx,'x',xi,'y',yi,'hDT',hdt);
        end

        function nm=lineNameFor(~,ln,k)
            nm=get(ln,'DisplayName'); if isempty(nm), nm=sprintf('Line_%d',k); end
        end
    end

    %% ===== Aligner (App UI) =====
    methods (Access=private)
        function refreshTables(obj)
            % Purge dead tips:
            %  - the parent line is gone, OR
            %  - the datatip graphics object was deleted by the user
            keep = true(1,numel(obj.Tips));
            for i=1:numel(obj.Tips)
                okLine = isgraphics(obj.Tips(i).hLine);
                okDT   = true;
                if ~isempty(obj.Tips(i).hDT)
                    okDT = isgraphics(obj.Tips(i).hDT);
                end
                if ~okLine || ~okDT
                    keep(i) = false;
                end
            end
            obj.Tips = obj.Tips(keep);

            % build main table rows
            if ~isempty(obj.UITable) && isgraphics(obj.UITable)
                n=numel(obj.Tips); C=cell(n,6);  % Only 6 columns now

                for i=1:n
                    s = obj.Tips(i);
                    C{i,1}=false;            % Select checkbox
                    C{i,2}=s.lineName;       % Signal Name
                    C{i,3}=s.x;              % X
                    C{i,4}=false;            % X□
                    C{i,5}=s.y;              % Y
                    C{i,6}=false;            % Y□
                end
                obj.UITable.Data = C;
                obj.applyTableStyles(obj.UITable);
            end

            % Update movement log text area
            obj.updateMovementLogTextArea();

            obj.PendingX=[]; obj.PendingY=[];
        end

        function onUITableEdit(obj, evt)
            r = evt.Indices(1); c = evt.Indices(2);
            val = logical(evt.NewData);
            C = obj.UITable.Data;

            if c==1          % Select checkbox - handle "choose all" functionality
                obj.handleSelectCheck(r, val, C);
            elseif c==4      % X□
                obj.handleAxisCheck('x', r, val, C);
            elseif c==6      % Y□
                obj.handleAxisCheck('y', r, val, C);
            end
        end

        function handleSelectCheck(obj, r, val, C)
            % Handle select checkbox - if this is the header row, toggle all
            % For now, just normal checkbox behavior
            C{r,1} = val;
            obj.UITable.Data = C;
        end

        function handleAxisCheck(obj, axisChar, r, val, C)
            if ~val
                if axisChar=='x' && ~isempty(obj.PendingX) && obj.PendingX.row==r
                    obj.PendingX=[];
                elseif axisChar=='y' && ~isempty(obj.PendingY) && obj.PendingY.row==r
                    obj.PendingY=[];
                end
                return;
            end

            switch axisChar
                case 'x'
                    if isempty(obj.PendingX)
                        s=obj.Tips(r);
                        obj.PendingX=struct('row',r,'hLine',s.hLine,'x',s.x);
                    else
                        mover=obj.PendingX; s2=obj.Tips(r);
                        if mover.hLine~=s2.hLine
                            dx = s2.x - mover.x;
                            obj.applyMove(mover.hLine, dx, 0, 'X');  % move + log
                        end
                        C{mover.row,4}=false; C{r,4}=false; obj.UITable.Data=C;
                        obj.PendingX=[]; obj.refreshTables();
                    end

                case 'y'
                    if isempty(obj.PendingY)
                        s=obj.Tips(r);
                        obj.PendingY=struct('row',r,'hLine',s.hLine,'y',s.y);
                    else
                        mover=obj.PendingY; s2=obj.Tips(r);
                        if mover.hLine~=s2.hLine
                            dy = s2.y - mover.y;
                            obj.applyMove(mover.hLine, 0, dy, 'Y');  % move + log
                        end
                        C{mover.row,6}=false; C{r,6}=false; obj.UITable.Data=C;
                        obj.PendingY=[]; obj.refreshTables();
                    end
            end
        end

        function applyMove(obj, hLine, dx, dy, axisChar)
            % Move the curve, update Tips, and history
            if ~isgraphics(hLine), return; end
            if dx~=0
                set(hLine,'XData', get(hLine,'XData') + dx);
            end
            if dy~=0
                set(hLine,'YData', get(hLine,'YData') + dy);
            end
            % update tip coordinates attached to this line
            for i=1:numel(obj.Tips)
                if obj.Tips(i).hLine == hLine
                    obj.Tips(i).x = obj.Tips(i).x + dx;
                    obj.Tips(i).y = obj.Tips(i).y + dy;
                end
            end
            % append move history (absolute distance moved this action)
            nm = get(hLine,'DisplayName'); if isempty(nm), nm = 'Line'; end

            % Create descriptive delta text
            deltaText = '';
            if dx ~= 0
                deltaText = sprintf('%s moved %s%.3f on X-axis', nm, obj.ternary(dx>0,'+','-'), abs(dx));
            end
            if dy ~= 0
                if ~isempty(deltaText)
                    deltaText = sprintf('%s, %s%.3f on Y-axis', deltaText, obj.ternary(dy>0,'+','-'), abs(dy));
                else
                    deltaText = sprintf('%s moved %s%.3f on Y-axis', nm, obj.ternary(dy>0,'+','-'), abs(dy));
                end
            end

            obj.MoveHistory(end+1) = struct( ...
                'Time',   datetime('now'), ...
                'Signal', string(nm), ...
                'Axis',   string(axisChar), ...
                'Delta',  abs(dx) + abs(dy), ...
                'Description', string(deltaText) );
        end

        function onSaveCSV(obj)
            if isempty(obj.Tips)
                uialert(obj.UIFig,'No datatips to save yet.','Nothing to export'); return;
            end
            [file,path] = uiputfile({'*.csv','CSV file (*.csv)';'*.txt','Text file (*.txt)'}, ...
                'Save datatip list as', obj.DefaultCSVPath);
            if isequal(file,0), return; end
            fname = fullfile(path,file);

            % Group tips by signal name and remove duplicates
            [uniqueSignals, ~, idx] = unique({obj.Tips.lineName});
            numUnique = length(uniqueSignals);
            
            % Preallocate arrays for unique data
            signalNames = cell(numUnique, 1);
            indices = zeros(numUnique, 1);
            xValues = zeros(numUnique, 1);
            yValues = zeros(numUnique, 1);
            
            % Extract one representative tip per signal
            for i = 1:numUnique
                firstIdx = find(idx == i, 1, 'first');
                signalNames{i} = obj.Tips(firstIdx).lineName;
                indices(i) = obj.Tips(firstIdx).idx;
                xValues(i) = obj.Tips(firstIdx).x;
                yValues(i) = obj.Tips(firstIdx).y;
            end
            
            % Create table with unique data
            S = struct('SignalName', signalNames, ...
                'Index', num2cell(indices), ...
                'X', num2cell(xValues), ...
                'Y', num2cell(yValues));
            T = struct2table(S);

            % write (overwrite or append prompt)
            if exist(fname,'file')
                choice = questdlg('File exists. Append or Overwrite?', ...
                    'File exists','Append','Overwrite','Cancel','Append');
                if strcmp(choice,'Cancel'), return; end
                if strcmp(choice,'Append')
                    try
                        Told = readtable(fname);
                        T = [Told; T];
                    catch
                    end
                end
            end
            try
                writetable(T,fname);
                uialert(obj.UIFig,['Saved ',num2str(numUnique),' unique signals to: ',fname],'Export complete','Icon','success');
            catch ME
                uialert(obj.UIFig,ME.message,'Failed to save','Icon','error');
            end
        end

        function onSendToWorkspace(obj)
            % Push datatips + move log to base workspace
            try
                % Group tips by signal name and remove duplicates
                if isempty(obj.Tips)
                    TipsOut = struct('SignalName',{}, 'Index',{}, 'X',{}, 'Y',{});
                else
                    [uniqueSignals, ~, idx] = unique({obj.Tips.lineName});
                    numUnique = length(uniqueSignals);
                    
                    % Preallocate arrays for unique data
                    signalNames = cell(numUnique, 1);
                    indices = zeros(numUnique, 1);
                    xValues = zeros(numUnique, 1);
                    yValues = zeros(numUnique, 1);
                    
                    % Extract one representative tip per signal
                    for i = 1:numUnique
                        firstIdx = find(idx == i, 1, 'first');
                        signalNames{i} = obj.Tips(firstIdx).lineName;
                        indices(i) = obj.Tips(firstIdx).idx;
                        xValues(i) = obj.Tips(firstIdx).x;
                        yValues(i) = obj.Tips(firstIdx).y;
                    end
                    
                    TipsOut = struct('SignalName', signalNames, ...
                        'Index', num2cell(indices), ...
                        'X', num2cell(xValues), ...
                        'Y', num2cell(yValues));
                end
                assignin('base','DataTipResults',TipsOut);

                if isempty(obj.MoveHistory)
                    MoveLogOut = table(datetime.empty(0,1),string.empty(0,1),string.empty(0,1),[]', ...
                        'VariableNames',{'Time','Signal','Axis','Delta'});
                else
                    MoveLogOut = struct2table(obj.MoveHistory);
                end
                assignin('base','MoveHistory',MoveLogOut);
                uialert(obj.UIFig,'Exported variables: DataTipResults, MoveHistory','Sent to Workspace','Icon','success');
            catch ME
                uialert(obj.UIFig,ME.message,'Workspace export failed','Icon','error');
            end
        end

        function onResetCurves(obj)
            if ~obj.CachedOriginals || isempty(obj.OriginalLines)
                return; % nothing cached — nothing to do
            end
            % restore every stored line
            for i=1:numel(obj.OriginalLines)
                rec = obj.OriginalLines(i);
                if isgraphics(rec.hLine)
                    try
                        set(rec.hLine,'XData',rec.X,'YData',rec.Y);
                    catch
                    end
                end
            end
            % clear move history
            obj.MoveHistory = struct('Time',{},'Signal',{},'Axis',{},'Delta',{},'Description',{});
            % refresh all tip coordinates from their original index
            for i=1:numel(obj.Tips)
                h = obj.Tips(i).hLine; idx = obj.Tips(i).idx;
                if isgraphics(h)
                    X = get(h,'XData'); Y = get(h,'YData');
                    if ~isempty(X) && idx <= numel(X)
                        obj.Tips(i).x = X(idx);
                        obj.Tips(i).y = Y(idx);
                    end
                end
            end
            obj.refreshTables();   % clears pending, repaints tables
        end

        function onShowHelp(obj)
            % Create comprehensive help dialog
            helpText = sprintf(['<h2>Interactive Data Tip Tool</h2>\n', ...
                '<p><b>Version:</b> 1.0<br>\n', ...
                '<b>Developer:</b> Ahmed Seleit</p>\n\n', ...
                '<h3>Overview</h3>\n', ...
                '<p>This tool allows you to create data tips on MATLAB plots by drawing lines with your mouse. ', ...
                'The DataTip Aligner window helps you manage and align these data tips precisely.</p>\n\n', ...
                '<h3>Mouse Controls</h3>\n', ...
                '<ul>\n', ...
                '<li><b>Left Click + Drag:</b> Draw free-form lines </li>\n', ...
                '<li><b>Right Click + Drag:</b> Draw horizontal lines (Y-locked)</li>\n', ...
                '<li><b>Middle Click + Drag:</b> Draw vertical lines (X-locked)</li>\n', ...
                '<li><b>Ctrl + Drag:</b> Create data tips only at Y=0 crossings</li>\n', ...
                '</ul>\n\n', ...
                '<h3>DataTip Aligner Window</h3>\n', ...
                '<p>The table shows all created data tips with the following columns:</p>\n', ...
                '<ul>\n', ...
                '<li><b>Signal Name:</b> Name of the intersected line</li>\n', ...
                '<li><b>X:</b> X-coordinate of the data tip</li>\n', ...
                '<li><b>Move X:</b> Checkbox to select this tip for X-alignment</li>\n', ...
                '<li><b>Y:</b> Y-coordinate of the data tip</li>\n', ...
                '<li><b>Move Y:</b> Checkbox to select this tip for Y-alignment</li>\n', ...
                '</ul>\n\n', ...
                '<h3>Alignment Process</h3>\n', ...
                '<ol>\n', ...
                '<li><b>Select Tips:</b> Check the Move X or Move Y boxes for exactly two data tips</li>\n', ...
                '<li><b>Review Values:</b> The left fields show the first selected tip''s coordinates, right fields show the second tip''s coordinates</li>\n', ...
                '<li><b>Align:</b> Click "Align X to" or "Align Y to" to move the first tip''s line to match the second tip''s coordinate</li>\n', ...
                '</ol>\n\n', ...
                '<h3>Button Functions</h3>\n', ...
                '<ul>\n', ...
                '<li><b>Refresh:</b> Update the table and remove deleted data tips</li>\n', ...
                '<li><b>Send to Workspace:</b> Export results to MATLAB workspace variable "DataTipResults"</li>\n', ...
                '<li><b>Save CSV:</b> Export data tips to a CSV file</li>\n', ...
                '<li><b>Reset:</b> Restore all modified lines to their original positions</li>\n', ...
                '<li><b>Help:</b> Show this help dialog</li>\n', ...
                '<li><b>Snap to:</b> Snap selected signals to arbitrary X,Y coordinates</li>\n', ...
                '</ul>']);

            % Create custom help dialog with README button
            obj.showHelpDialog(helpText);
        end

        function showHelpDialog(obj, helpText)
            % Create a custom help dialog with README button
            helpFig = uifigure('Name', 'Interactive Data Tip Tool - Help', ...
                'Position', [100, 100, 600, 700], ...
                'Resize', 'off', ...
                'WindowStyle', 'modal');

            % HTML text area for help content (no assignment needed)
            uihtml(helpFig, 'Position', [20, 60, 560, 620], 'HTMLSource', helpText);

            % README button (no assignment needed)
            uibutton(helpFig, 'Position', [20, 20, 120, 25], 'Text', 'Open README', ...
                'ButtonPushedFcn', @(~,~)obj.openReadmeFile(), 'Tooltip', 'Open the README.md file');

            % Close button (no assignment needed)
            uibutton(helpFig, 'Position', [460, 20, 120, 25], 'Text', 'Close', ...
                'ButtonPushedFcn', @(~,~)close(helpFig));
        end

        function openReadmeFile(obj)
            % Open the README.md file
            try
                % Get the directory where this tool is located
                toolDir = fileparts(which('InteractiveDataTipTool'));
                readmePath = fullfile(toolDir, 'README.md');

                if exist(readmePath, 'file')
                    % Try to open with system editor
                    if ispc
                        system(['start "" "' readmePath '"']);
                    elseif ismac
                        system(['open "' readmePath '"']);
                    else
                        system(['xdg-open "' readmePath '"']);
                    end
                else
                    uialert(obj.UIFig, 'README.md file not found in tool directory.', 'File Not Found', 'Icon', 'warning');
                end
            catch ME
                uialert(obj.UIFig, ['Failed to open README.md: ' ME.message], 'Error Opening File', 'Icon', 'error');
            end
        end

        function onSnapToExecute(obj)
            % Execute the snap operation using selected checkboxes
            C = obj.UITable.Data;
            if isempty(C)
                uialert(obj.UIFig, 'No data tips available to snap.', 'No Data Tips');
                return;
            end

            % Get selected tips from checkbox column
            selectedRows = find([C{:, 1}]);  % First column is Select checkbox
            if isempty(selectedRows)
                uialert(obj.UIFig, 'Please select at least one data tip to snap.', 'No Selection');
                return;
            end

            targetX = obj.SnapToXField.Value;
            targetY = obj.SnapToYField.Value;

            % Get selected tips and ensure only one tip per signal is selected
            selectedTips = obj.Tips(selectedRows);
            handles = [selectedTips.hLine];
            % Check for duplicates (more than one tip from same signal)
            [uniqueHandles,~,ic] = unique(handles);
            counts = accumarray(ic(:), 1);
            if any(counts>1)
                uialert(obj.UIFig, 'Please select only one data tip from each signal to snap to target.', 'Invalid Selection', 'Icon', 'error');
                return;
            end

            % Snap each unique line
            for i = 1:length(uniqueHandles)
                hLine = uniqueHandles(i);
                obj.snapLineToPoint(hLine, targetX, targetY);
            end

            % Update tables
            obj.refreshTables();

            % Show success message
            uialert(obj.UIFig, sprintf('Snapped %d signal(s) to point (%.3f, %.3f)', ...
                length(uniqueHandles), targetX, targetY), ...
                'Snap Complete', 'Icon', 'success');
        end

        function onSendSelectedToWorkspace(obj)
            % Send only selected tips to workspace
            C = obj.UITable.Data;
            if isempty(C)
                uialert(obj.UIFig, 'No data tips available.', 'No Data Tips');
                return;
            end

            selectedRows = find([C{:, 1}]);
            if isempty(selectedRows)
                uialert(obj.UIFig, 'Please select at least one data tip.', 'No Selection');
                return;
            end

            try
                selectedTips = obj.Tips(selectedRows);
                
                % Group selected tips by signal name and remove duplicates
                [uniqueSignals, ~, idx] = unique({selectedTips.lineName});
                numUnique = length(uniqueSignals);
                
                % Preallocate arrays for unique data
                signalNames = cell(numUnique, 1);
                indices = zeros(numUnique, 1);
                xValues = zeros(numUnique, 1);
                yValues = zeros(numUnique, 1);
                
                % Extract one representative tip per signal
                for i = 1:numUnique
                    firstIdx = find(idx == i, 1, 'first');
                    signalNames{i} = selectedTips(firstIdx).lineName;
                    indices(i) = selectedTips(firstIdx).idx;
                    xValues(i) = selectedTips(firstIdx).x;
                    yValues(i) = selectedTips(firstIdx).y;
                end
                
                TipsOut = struct('SignalName', signalNames, ...
                    'Index', num2cell(indices), ...
                    'X', num2cell(xValues), ...
                    'Y', num2cell(yValues));
                assignin('base','SelectedDataTipResults',TipsOut);

                uialert(obj.UIFig, sprintf('Exported %d unique signal(s) from %d selected data tips to variable: SelectedDataTipResults', ...
                    numUnique, length(selectedRows)), 'Sent to Workspace', 'Icon', 'success');
            catch ME
                uialert(obj.UIFig,ME.message,'Workspace export failed','Icon','error');
            end
        end

        function onSaveSelectedCSV(obj)
            % Save only selected tips to CSV
            C = obj.UITable.Data;
            if isempty(C)
                uialert(obj.UIFig, 'No data tips available.', 'No Data Tips');
                return;
            end

            selectedRows = find([C{:, 1}]);
            if isempty(selectedRows)
                uialert(obj.UIFig, 'Please select at least one data tip.', 'No Selection');
                return;
            end

            [file,path] = uiputfile({'*.csv','CSV file (*.csv)';'*.txt','Text file (*.txt)'}, ...
                'Save selected datatips as', obj.DefaultCSVPath);
            if isequal(file,0), return; end
            fname = fullfile(path,file);

            selectedTips = obj.Tips(selectedRows);
            
            % Group selected tips by signal name and remove duplicates
            [uniqueSignals, ~, idx] = unique({selectedTips.lineName});
            numUnique = length(uniqueSignals);
            
            % Preallocate arrays for unique data
            signalNames = cell(numUnique, 1);
            indices = zeros(numUnique, 1);
            xValues = zeros(numUnique, 1);
            yValues = zeros(numUnique, 1);
            
            % Extract one representative tip per signal
            for i = 1:numUnique
                firstIdx = find(idx == i, 1, 'first');
                signalNames{i} = selectedTips(firstIdx).lineName;
                indices(i) = selectedTips(firstIdx).idx;
                xValues(i) = selectedTips(firstIdx).x;
                yValues(i) = selectedTips(firstIdx).y;
            end
            
            S = struct('SignalName', signalNames, ...
                'Index', num2cell(indices), ...
                'X', num2cell(xValues), ...
                'Y', num2cell(yValues));
            T = struct2table(S);

            try
                writetable(T,fname);
                uialert(obj.UIFig,['Saved ',num2str(numUnique),' unique signals from ', ...
                    num2str(length(selectedRows)),' selected tips to: ',fname], ...
                    'Export complete','Icon','success');
            catch ME
                uialert(obj.UIFig,ME.message,'Failed to save','Icon','error');
            end
        end

        function onSelectAllToggle(obj)
            % Toggle select all functionality
            C = obj.UITable.Data;
            if isempty(C), return; end

            % Check if all are currently selected
            allSelected = all([C{:,1}]);

            % Toggle all checkboxes
            for i = 1:size(C, 1)
                C{i, 1} = ~allSelected;
            end

            obj.UITable.Data = C;
        end

        function snapLineToPoint(obj, hLine, targetX, targetY)
            % Snap a line to a target point by moving it
            if ~isgraphics(hLine), return; end

            % Find the first tip on this line to determine current position
            tipIdx = find([obj.Tips.hLine] == hLine, 1);
            if isempty(tipIdx), return; end

            currentX = obj.Tips(tipIdx).x;
            currentY = obj.Tips(tipIdx).y;

            % Calculate required movement
            dx = targetX - currentX;
            dy = targetY - currentY;

            % Apply the movement using existing method
            obj.applyMove(hLine, dx, dy, 'snap');
        end

        function cacheOriginalLines(obj)
            if obj.CachedOriginals, return; end
            L = findobj(obj.Ax,'Type','line');
            % Preallocate struct array for better performance
            numLines = numel(L);
            tmp = struct('hLine',cell(numLines,1),'X',cell(numLines,1),'Y',cell(numLines,1));
            for k=1:numLines
                ln = L(k);
                tmp(k) = struct('hLine',ln, ...
                    'X',get(ln,'XData'), ...
                    'Y',get(ln,'YData'));
            end
            obj.OriginalLines = tmp;
            obj.CachedOriginals = true;
        end

        function applyTableStyles(~, tbl)
            % center all columns + alternating row colors
            try
                sc = tbl.StyleConfigurations;
                for k = 1:numel(sc), removeStyle(tbl, sc(k).Style); end
            catch
            end
            try
                stCenter = uistyle('HorizontalAlignment','center');
                addStyle(tbl, stCenter, 'column', 1:size(tbl.Data,2));
            catch
            end
            try
                n = size(tbl.Data,1);
                if n>0
                    st1 = uistyle('BackgroundColor',[0.90 0.95 1.00]); % light blue
                    st2 = uistyle('BackgroundColor',[0.96 0.98 1.00]); % lighter blue
                    addStyle(tbl, st1, 'row', 1:2:n);
                    addStyle(tbl, st2, 'row', 2:2:n);
                end
            catch
            end
        end
    end

    %% ===== helpers =====
    methods (Access=private)
        function tf = isFigureModeActive(obj)
            tf=false;
            try
                z=zoom(obj.Fig);
                if strcmpi(z.Enable,'on'), tf=true; return; end
            catch
            end
            try
                p=pan(obj.Fig);
                if strcmpi(p.Enable,'on'), tf=true; return; end
            catch
            end
            try
                r=rotate3d(obj.Fig);
                if strcmpi(r.Enable,'on'), tf=true; return; end
            catch
            end
            try
                d=datacursormode(obj.Fig);
                if strcmpi(d.Enable,'on'), tf=true; return; end
            catch
            end
            try
                b=brush(obj.Fig);
                if strcmpi(b.Enable,'on'), tf=true; return; end
            catch
            end
        end

        function s = allDeltaForSignal(~, ~)
            % This method is no longer used - replaced by getAllMovementHistory
            s = '';
        end

        function updateMovementLogTextArea(obj)
            % Update the text area with all movement history
            if isempty(obj.MoveLogTextArea) || ~isgraphics(obj.MoveLogTextArea)
                return;
            end

            if isempty(obj.MoveHistory)
                obj.MoveLogTextArea.Value = {'Movement Log:', '(No movements yet)'};
            else
                numMoves = numel(obj.MoveHistory);
                % Preallocate cell array for better performance
                logLines = cell(numMoves + 1, 1);  % +1 for header
                logLines{1} = 'Movement Log:';
                lineIdx = 2;
                for k = 1:numMoves
                    mh = obj.MoveHistory(k);
                    if isfield(mh,'Description') && ~isempty(mh.Description)
                        logLines{lineIdx} = char(mh.Description);
                        lineIdx = lineIdx + 1;
                    elseif isfield(mh,'Signal') && isfield(mh,'Delta')
                        logLines{lineIdx} = sprintf('%s: Δ = %.3f', string(mh.Signal), mh.Delta);
                        lineIdx = lineIdx + 1;
                    end
                end
                % Trim unused cells if any
                logLines = logLines(1:lineIdx-1);
                obj.MoveLogTextArea.Value = logLines;
            end
        end

        function s = getAllMovementHistory(obj)
            % Return all movement history as a single wrapped text string
            s = '';
            if isempty(obj.MoveHistory), return; end

            numMoves = numel(obj.MoveHistory);
            % Preallocate cell array for better performance
            descriptions = cell(numMoves, 1);
            descIdx = 1;
            for k = 1:numMoves
                mh = obj.MoveHistory(k);
                if isfield(mh,'Description') && ~isempty(mh.Description)
                    descriptions{descIdx} = char(mh.Description);
                    descIdx = descIdx + 1;
                elseif isfield(mh,'Signal') && isfield(mh,'Delta')
                    descriptions{descIdx} = sprintf('%s: Δ = %.3f', string(mh.Signal), mh.Delta);
                    descIdx = descIdx + 1;
                end
            end
            % Trim unused cells if any
            descriptions = descriptions(1:descIdx-1);

            % Join all descriptions with newlines for multi-line display
            if ~isempty(descriptions)
                s = strjoin(descriptions, newline);
            end
        end

        function out = ternary(~, cond, a, b)
            % Simple inline conditional helper
            if cond, out = a; else, out = b; end
        end

        function clearPreview(obj)
            if ~isempty(obj.PreviewLine) && isgraphics(obj.PreviewLine), delete(obj.PreviewLine); end
            obj.PreviewLine=[];
        end

        function [hit, pt] = lineIntersect(~, p1, p2, p3, p4)
            x1=p1(1); y1=p1(2); x2=p2(1); y2=p2(2);
            x3=p3(1); y3=p3(2); x4=p4(1); y4=p4(2);
            denom=(x1-x2)*(y3-y4)-(y1-y2)*(x3-x4);
            if abs(denom)<1e-12, hit=false; pt=[NaN NaN]; return; end
            t=((x1-x3)*(y3-y4)-(y1-y3)*(x3-x4))/denom;
            u=-((x1-x2)*(y1-y3)-(y1-y2)*(x1-x3))/denom;
            if t>=0 && t<=1 && u>=0 && u<=1
                pt=[x1+t*(x2-x1), y1+t*(y2-y1)];
                hit=true;
            else
                hit=false;
                pt=[NaN NaN];
            end
        end
    end
end
