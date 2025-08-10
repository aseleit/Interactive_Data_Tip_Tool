% InteractiveDataTipTool is a class to create an interactive feature with
% Matlab figures that creates Data Tips by intersection of a straight line
% via mouse and keyboard prompts. 
% DataTip tool using mouse button combinations and keyboard modifiers
% Left click + drag = free line
% Right click + drag = horizontal line  
% Middle click + drag = vertical line
% Ctrl + drag = x-axis datatips at y=0

classdef InteractiveDataTipTool < handle
    
    properties
        Ax
        Enable = false
        Fig
        PreviewLine = []
        IsDown = false
        StartPoint = [NaN NaN]
        ConstraintMode = 'free'  % 'free', 'horizontal', 'vertical'
        CSVFilename = ''  % Single CSV file for all datatips
    end
    
    methods
        function obj = InteractiveDataTipTool(ax)
            obj.Ax = ax;
            obj.Fig = ancestor(ax,'figure');
            
            % Initialize single CSV file with timestamp
            timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
            obj.CSVFilename = fullfile(pwd, sprintf('datatip_results_%s.csv', timestamp));
        end
        
        function setEnabled(obj, val)
            obj.Enable = logical(val);
            if obj.Enable
                obj.Fig.Pointer = 'crosshair';
                obj.Fig.WindowButtonDownFcn = @(~,~)obj.mouseDown();
                obj.Fig.WindowButtonMotionFcn = @(~,~)obj.mouseMove();
                obj.Fig.WindowButtonUpFcn = @(~,~)obj.mouseUp();
                % Disable conflicting tools
                zoom(obj.Fig,'off'); pan(obj.Fig,'off'); datacursormode(obj.Fig,'off');
                fprintf('Mouse Constraint Tool enabled:\n');
                fprintf('  LEFT click + drag = Free line\n');
                fprintf('  RIGHT click + drag = Horizontal line\n');
                fprintf('  MIDDLE click + drag = Vertical line\n');
                fprintf('  CTRL + drag = X-axis datatips at y=0\n');
                fprintf('  CSV file: %s\n', obj.CSVFilename);
            else
                obj.Fig.Pointer = 'arrow';
                obj.Fig.WindowButtonDownFcn = [];
                obj.Fig.WindowButtonMotionFcn = [];
                obj.Fig.WindowButtonUpFcn = [];
                obj.clearPreview();
            end
        end
        
        function mouseDown(obj)
            if ~obj.Enable, return; end
            
            % Check if we're in the right axes
            h = hittest(obj.Fig);
            ax = ancestor(h,'axes');
            if isempty(ax) || ax ~= obj.Ax
                fprintf('Not in target axes, ignoring\n');
                return;
            end
            
            % Check for Ctrl modifier first (special x-axis mode)
            modifiers = get(obj.Fig, 'CurrentModifier');
            if any(contains(modifiers, {'control', 'command'}))
                obj.ConstraintMode = 'x-axis';
                fprintf('CTRL held - X-AXIS mode (datatips at y=0)\n');
            else
                % Determine constraint mode based on mouse button
                selType = get(obj.Fig, 'SelectionType');
                switch selType
                    case 'normal'    % Left click
                        obj.ConstraintMode = 'free';
                        fprintf('LEFT click detected - FREE line mode\n');
                    case 'alt'       % Right click  
                        obj.ConstraintMode = 'horizontal';
                        fprintf('RIGHT click detected - HORIZONTAL line mode\n');
                    case 'extend'    % Middle click (or Shift+click)
                        obj.ConstraintMode = 'vertical';
                        fprintf('MIDDLE click detected - VERTICAL line mode\n');
                    otherwise
                        obj.ConstraintMode = 'free';
                        fprintf('Other click (%s) - FREE line mode\n', selType);
                end
            end
            
            obj.IsDown = true;
            obj.StartPoint = obj.Ax.CurrentPoint(1,1:2);
            fprintf('Starting %s line at [%.2f, %.2f]\n', obj.ConstraintMode, obj.StartPoint(1), obj.StartPoint(2));
            
            % Create preview line
            obj.clearPreview();
            obj.PreviewLine = line(obj.Ax, obj.StartPoint(1), obj.StartPoint(2), ...
                'Color', 'r', 'LineStyle', '--', 'LineWidth', 3, ...
                'Marker', 'o', 'MarkerSize', 6, ...
                'HitTest', 'off', 'PickableParts', 'none');
            fprintf('Preview line created\n');
            drawnow;
        end
        
        function mouseMove(obj)
            if ~obj.Enable || ~obj.IsDown || isempty(obj.PreviewLine), return; end
            
            curr = obj.Ax.CurrentPoint(1,1:2);
            p0 = obj.StartPoint;
            p1 = curr;
            
            % Apply constraints based on mode
            switch obj.ConstraintMode
                case 'horizontal'
                    p1(2) = p0(2); % Lock Y coordinate
                    fprintf('Horizontal: y=%.2f (from [%.2f,%.2f] to [%.2f,%.2f])\n', p1(2), curr(1), curr(2), p1(1), p1(2));
                case 'vertical'
                    p1(1) = p0(1); % Lock X coordinate
                    fprintf('Vertical: x=%.2f (from [%.2f,%.2f] to [%.2f,%.2f])\n', p1(1), curr(1), curr(2), p1(1), p1(2));
                case 'x-axis'
                    p1(2) = 0; % Force Y to 0 (x-axis)
                    fprintf('X-axis: y=0 (from [%.2f,%.2f] to [%.2f,%.2f])\n', curr(1), curr(2), p1(1), p1(2));
                case 'free'
                    % No constraint
            end
            
            % Update preview line
            set(obj.PreviewLine, 'XData', [p0(1) p1(1)], 'YData', [p0(2) p1(2)]);
            drawnow limitrate;
        end
        
        function mouseUp(obj)
            if ~obj.Enable || ~obj.IsDown, return; end
            fprintf('Mouse up detected\n');
            
            curr = obj.Ax.CurrentPoint(1,1:2);
            p0 = obj.StartPoint;
            p1 = curr;
            
            % Apply final constraints
            switch obj.ConstraintMode
                case 'horizontal'
                    p1(2) = p0(2);
                case 'vertical'
                    p1(1) = p0(1);
                case 'x-axis'
                    p1(2) = 0; % Force Y to 0 (x-axis)
            end
            
            fprintf('Final %s line: [%.2f,%.2f] to [%.2f,%.2f]\n', obj.ConstraintMode, p0(1), p0(2), p1(1), p1(2));
            
            % Find intersections and create datatips
            obj.createDataTips(p0, p1);
            
            % Clean up
            obj.clearPreview();
            obj.IsDown = false;
            obj.ConstraintMode = 'free';
        end
        
        function clearPreview(obj)
            if ~isempty(obj.PreviewLine) && isgraphics(obj.PreviewLine)
                delete(obj.PreviewLine);
                fprintf('Preview line cleared\n');
            end
            obj.PreviewLine = [];
        end
        
        function createDataTips(obj, p0, p1)
            % Find intersections and create datatips
            kids = findobj(obj.Ax, 'Type', 'line');
            count = 0;
            results = struct('x', {}, 'y', {}, 'line_name', {}, 'constraint_mode', {});
            
            if strcmp(obj.ConstraintMode, 'x-axis')
                % Special x-axis mode: create datatips on x-axis at y=0
                % Find x-coordinates within the range specified by the line
                xRange = sort([p0(1), p1(1)]);
                
                for k = 1:numel(kids)
                    ln = kids(k);
                    if ~strcmp(get(ln,'Visible'),'on'), continue; end
                    x = get(ln,'XData'); y = get(ln,'YData');
                    
                    % Get line name from DisplayName or create one
                    lineName = get(ln, 'DisplayName');
                    if isempty(lineName)
                        lineName = sprintf('Line_%d', k);
                    end
                    
                    % Find where the line crosses y=0 within our x-range
                    for i = 1:numel(x)-1
                        x1 = x(i); y1 = y(i);
                        x2 = x(i+1); y2 = y(i+1);
                        
                        % Check if segment crosses y=0
                        if (y1 <= 0 && y2 >= 0) || (y1 >= 0 && y2 <= 0)
                            % Find x-coordinate where line crosses y=0
                            if y2 ~= y1
                                xCross = x1 + (0 - y1) * (x2 - x1) / (y2 - y1);
                                
                                % Check if crossing is within our x-range
                                if xCross >= xRange(1) && xCross <= xRange(2)
                                    try
                                        datatip(ln, xCross, 0);
                                        count = count + 1;
                                        
                                        % Store result
                                        results(end+1) = struct('x', xCross, 'y', 0, ...
                                            'line_name', lineName, 'constraint_mode', 'x-axis');
                                        
                                    catch
                                        % Fallback for older MATLAB
                                        fprintf('  X-axis datatip at [%.3f, 0] on %s\n', xCross, lineName);
                                        results(end+1) = struct('x', xCross, 'y', 0, ...
                                            'line_name', lineName, 'constraint_mode', 'x-axis');
                                    end
                                end
                            end
                        end
                    end
                    
                    % Also check if any points are exactly at y=0 within our range
                    for i = 1:numel(x)
                        if abs(y(i)) < 1e-10 && x(i) >= xRange(1) && x(i) <= xRange(2)
                            try
                                datatip(ln, x(i), 0);
                                count = count + 1;
                                
                                % Store result
                                results(end+1) = struct('x', x(i), 'y', 0, ...
                                    'line_name', lineName, 'constraint_mode', 'x-axis');
                                
                            catch
                                % Fallback for older MATLAB
                                fprintf('  X-axis datatip at [%.3f, 0] on %s\n', x(i), lineName);
                                results(end+1) = struct('x', x(i), 'y', 0, ...
                                    'line_name', lineName, 'constraint_mode', 'x-axis');
                            end
                        end
                    end
                end
            else
                % Normal mode: find line intersections
                for k = 1:numel(kids)
                    ln = kids(k);
                    if ~strcmp(get(ln,'Visible'),'on'), continue; end
                    x = get(ln,'XData'); y = get(ln,'YData');
                    
                    % Get line name from DisplayName or create one
                    lineName = get(ln, 'DisplayName');
                    if isempty(lineName)
                        lineName = sprintf('Line_%d', k);
                    end
                    
                    % Find intersections for each segment
                    for i = 1:numel(x)-1
                        [hit, pt] = obj.lineIntersect(p0, p1, [x(i) y(i)], [x(i+1) y(i+1)]);
                        if hit
                            try
                                datatip(ln, pt(1), pt(2));
                                count = count + 1;
                                
                                % Store result
                                results(end+1) = struct('x', pt(1), 'y', pt(2), ...
                                    'line_name', lineName, 'constraint_mode', obj.ConstraintMode);
                                
                            catch
                                % Fallback for older MATLAB
                                fprintf('  Datatip at [%.3f, %.3f] on %s\n', pt(1), pt(2), lineName);
                                results(end+1) = struct('x', pt(1), 'y', pt(2), ...
                                    'line_name', lineName, 'constraint_mode', obj.ConstraintMode);
                            end
                        end
                    end
                end
            end
            
            % Save to workspace
            obj.saveToWorkspace(results);
            
            % Export to CSV
            obj.exportToCSV(results);
            
            fprintf('Created %d datatips\n', count);
        end
        
        function saveToWorkspace(~, results)
            % Save results to base workspace
            try
                if evalin('base', 'exist(''DataTipResults'', ''var'')')
                    % Append to existing results
                    existingResults = evalin('base', 'DataTipResults');
                    allResults = [existingResults; results];
                else
                    % Create new results
                    allResults = results;
                end
                assignin('base', 'DataTipResults', allResults);
                fprintf('Saved %d datatips to workspace variable ''DataTipResults''\n', length(results));
            catch ME
                warning('DataTipTool:WorkspaceSave', 'Failed to save to workspace: %s', ME.message);
            end
        end
        
        function exportToCSV(obj, results)
            % Export results to a single CSV file (append mode)
            if isempty(results)
                return;
            end
            
            try
                % Create table from results
                newDataTable = struct2table(results);
                
                % Add timestamp column for this batch
                batchTime = repmat({datestr(now, 'yyyy-mm-dd HH:MM:SS')}, height(newDataTable), 1);
                newDataTable.timestamp = batchTime;
                
                % Check if CSV file already exists
                if exist(obj.CSVFilename, 'file')
                    % Read existing data
                    try
                        existingTable = readtable(obj.CSVFilename);
                        % Append new data
                        combinedTable = [existingTable; newDataTable];
                        fprintf('Appending %d new datatips to existing CSV file\n', height(newDataTable));
                    catch
                        % If reading fails, just use new data
                        combinedTable = newDataTable;
                        fprintf('Creating new CSV file with %d datatips\n', height(newDataTable));
                    end
                else
                    % Create new file
                    combinedTable = newDataTable;
                    fprintf('Creating new CSV file: %s\n', obj.CSVFilename);
                end
                
                % Write combined data to CSV
                writetable(combinedTable, obj.CSVFilename);
                fprintf('Total datatips in CSV: %d (file: %s)\n', height(combinedTable), obj.CSVFilename);
                
            catch ME
                warning('DataTipTool:CSVExport', 'Failed to export to CSV: %s', ME.message);
                fprintf('Results available in workspace variable ''DataTipResults''\n');
            end
        end
        
        function [hit, pt] = lineIntersect(~, p1, p2, p3, p4)
            % Line segment intersection
            x1=p1(1); y1=p1(2); x2=p2(1); y2=p2(2);
            x3=p3(1); y3=p3(2); x4=p4(1); y4=p4(2);
            
            denom = (x1-x2)*(y3-y4) - (y1-y2)*(x3-x4);
            if abs(denom) < 1e-10
                hit = false; pt = [NaN NaN]; return;
            end
            
            t = ((x1-x3)*(y3-y4) - (y1-y3)*(x3-x4)) / denom;
            u = -((x1-x2)*(y1-y3) - (y1-y2)*(x1-x3)) / denom;
            
            if t >= 0 && t <= 1 && u >= 0 && u <= 1
                pt = [x1 + t*(x2-x1), y1 + t*(y2-y1)];
                hit = true;
            else
                hit = false; pt = [NaN NaN];
            end
        end
    end
end
