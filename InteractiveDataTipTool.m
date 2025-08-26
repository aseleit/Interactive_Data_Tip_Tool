classdef InteractiveDataTipTool < handle
    % - Draw a line (left=free, right=horizontal, middle=vertical, Ctrl=x-axis)
    % - Intersections create native datatips (snapped to nearest vertex)
    % - Aligner table:  Signal Name | X | X□ | Y | Y□
    %   First checked box = mover; second = target. Same-curve ⇒ no-op.
    % - A Move Log on the right records each individual |Δ| as a new row.
    % - Buttons: Refresh, Send to Workspace, Save CSV, Reset (restores all curves)
    % - ESC cancels a line; Zoom/Pan/Rotate/DataCursor/Brush disable drawing
    %
    % NEW:
    % - Refresh now removes rows whose datatips were deleted by the user
    % - "Difference" column removed everywhere

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
        MoveLogTable       % right-side one-column log (Δ per action)
        BtnSave
        BtnRefresh
        BtnToWS
        BtnReset

        % pending (first selection)
        PendingX = []      % struct('row',r,'hLine',h,'x',val)
        PendingY = []      % struct('row',r,'hLine',h,'y',val)

        % Move history list
        MoveHistory = struct('Time',{},'Signal',{},'Axis',{},'Delta',{})

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
                sprintf('datatips_%s.csv', datestr(now,'yyyy-mm-dd_HHMMSS')));
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
            pos = [120 100 720 360];
            if ~isempty(varargin) && isnumeric(varargin{1}) && numel(varargin{1})==4
                pos = varargin{1}; varargin = varargin(2:end);
            end
            p = inputParser; addParameter(p,'Position',pos,@(v)isnumeric(v)&&numel(v)==4);
            parse(p,varargin{:}); pos = p.Results.Position;

            if isempty(obj.UIFig) || ~isgraphics(obj.UIFig)
                obj.UIFig = uifigure('Name','DataTip Aligner', 'Position', pos);
            else
                obj.UIFig.Position = pos; figure(obj.UIFig);
            end

            % Buttons
            if isempty(obj.BtnRefresh) || ~isgraphics(obj.BtnRefresh)
                obj.BtnRefresh = uibutton(obj.UIFig,'Text','Refresh', ...
                    'Position',[16 12 110 30], ...
                    'ButtonPushedFcn', @(~,~)obj.refreshTables());
            end
            if isempty(obj.BtnToWS) || ~isgraphics(obj.BtnToWS)
                obj.BtnToWS = uibutton(obj.UIFig,'Text','Send to Workspace', ...
                    'Position',[140 12 160 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onSendToWorkspace());
            end
            if isempty(obj.BtnSave) || ~isgraphics(obj.BtnSave)
                obj.BtnSave = uibutton(obj.UIFig,'Text','Save CSV', ...
                    'Position',[312 12 120 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onSaveCSV());
            end
            if isempty(obj.BtnReset) || ~isgraphics(obj.BtnReset)
                obj.BtnReset = uibutton(obj.UIFig,'Text','Reset', ...
                    'Position',[444 12 110 30], ...
                    'ButtonPushedFcn', @(~,~)obj.onResetCurves());
            end

            % Main table (left): Signal Name | X | X□ | Y | Y□
            if isempty(obj.UITable) || ~isgraphics(obj.UITable)
                obj.UITable = uitable(obj.UIFig, ...
                    'Position',[10 54 pos(3)-220 pos(4)-66], ...
                    'RowName',[], ...
                    'ColumnName', {'Signal Name','X','X□','Y','Y□'}, ...
                    'ColumnEditable', [false false true false true], ...
                    'ColumnFormat', {'char','numeric','logical','numeric','logical'}, ...
                    'ColumnSortable', [true true false true false], ...
                    'CellEditCallback', @(src,evt)obj.onUITableEdit(evt));
            end

            % Move Log table (right) – Δ for each action
            if isempty(obj.MoveLogTable) || ~isgraphics(obj.MoveLogTable)
                obj.MoveLogTable = uitable(obj.UIFig, ...
                    'Position',[pos(3)-200 54 190 pos(4)-66], ...
                    'RowName',[], ...
                    'ColumnName', {'Δ Log'}, ...
                    'ColumnSortable', true, ...
                    'ColumnEditable', false, ...
                    'ColumnFormat', {'numeric'});
            end

            obj.refreshTables();
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
            set(obj.PreviewLine,'XData',[p0(1) p1(1)],'YData',[p0(2) p1(2)]); drawnow limitrate;
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
                case 'x-axis',     p1(2)=0;
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
            hdt=[]; try, hdt=datatip(ln,xi,yi); catch, end %#ok<NASGU>
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
                n=numel(obj.Tips); C=cell(n,5);
                for i=1:n
                    s = obj.Tips(i);
                    C{i,1}=s.lineName;
                    C{i,2}=s.x;
                    C{i,3}=false;            % X□
                    C{i,4}=s.y;
                    C{i,5}=false;            % Y□
                end
                obj.UITable.Data = C;
                obj.applyTableStyles(obj.UITable);
            end

            % build move log table
            if ~isempty(obj.MoveLogTable) && isgraphics(obj.MoveLogTable)
                if isempty(obj.MoveHistory)
                    obj.MoveLogTable.Data = {};
                else
                    obj.MoveLogTable.Data = num2cell([obj.MoveHistory.Delta].');
                end
                obj.applyTableStyles(obj.MoveLogTable);
            end

            obj.PendingX=[]; obj.PendingY=[];
        end

        function onUITableEdit(obj, evt)
            r = evt.Indices(1); c = evt.Indices(2);
            val = logical(evt.NewData);
            C = obj.UITable.Data;

            if c==3          % X□
                obj.handleAxisCheck('x', r, val, C);
            elseif c==5      % Y□
                obj.handleAxisCheck('y', r, val, C);
            end
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
                        C{mover.row,3}=false; C{r,3}=false; obj.UITable.Data=C;
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
                        C{mover.row,5}=false; C{r,5}=false; obj.UITable.Data=C;
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
            obj.MoveHistory(end+1) = struct( ...
                'Time',   datetime('now'), ...
                'Signal', string(nm), ...
                'Axis',   string(axisChar), ...
                'Delta',  abs(dx) + abs(dy) );
        end

        function onSaveCSV(obj)
            if isempty(obj.Tips)
                uialert(obj.UIFig,'No datatips to save yet.','Nothing to export'); return;
            end
            [file,path] = uiputfile({'*.csv','CSV file (*.csv)';'*.txt','Text file (*.txt)'}, ...
                                    'Save datatip list as', obj.DefaultCSVPath);
            if isequal(file,0), return; end
            fname = fullfile(path,file);

            % datatips table
            S = struct('SignalName',{obj.Tips.lineName}', ...
                       'Index',[obj.Tips.idx]', ...
                       'X',[obj.Tips.x]', ...
                       'Y',[obj.Tips.y]');
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
                uialert(obj.UIFig,['Saved to: ',fname],'Export complete','Icon','success');
            catch ME
                uialert(obj.UIFig,ME.message,'Failed to save','Icon','error');
            end
        end

        function onSendToWorkspace(obj)
            % Push datatips + move log to base workspace
            try
                TipsOut = struct('SignalName',{obj.Tips.lineName}', ...
                                 'Index',[obj.Tips.idx]', ...
                                 'X',[obj.Tips.x]', ...
                                 'Y',[obj.Tips.y]');
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
            obj.MoveHistory = struct('Time',{},'Signal',{},'Axis',{},'Delta',{});
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

        function cacheOriginalLines(obj)
            if obj.CachedOriginals, return; end
            L = findobj(obj.Ax,'Type','line');
            % Properly initialize an empty struct array
            tmp = struct('hLine',{},'X',{},'Y',{});
            for k=1:numel(L)
                ln = L(k);
                tmp(end+1) = struct('hLine',ln, ...
                                    'X',get(ln,'XData'), ...
                                    'Y',get(ln,'YData'));
            end
            obj.OriginalLines = tmp;
            obj.CachedOriginals = true;
        end

        function applyTableStyles(obj, tbl)
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
            try, z=zoom(obj.Fig);           if strcmpi(z.Enable,'on'), tf=true; return; end, end
            try, p=pan(obj.Fig);            if strcmpi(p.Enable,'on'), tf=true; return; end, end
            try, r=rotate3d(obj.Fig);       if strcmpi(r.Enable,'on'), tf=true; return; end, end
            try, d=datacursormode(obj.Fig); if strcmpi(d.Enable,'on'), tf=true; return; end, end
            try, b=brush(obj.Fig);          if strcmpi(b.Enable,'on'), tf=true; return; end, end
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
                pt=[x1+t*(x2-x1), y1+t*(y2-y1)]; hit=true;
            else, hit=false; pt=[NaN NaN]; end
        end
    end
end
