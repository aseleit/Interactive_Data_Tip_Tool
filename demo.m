function demo()
clc;
fprintf('==========================================\n');
fprintf('Interactive Data Tip Tool\n');
fprintf('==========================================\n');

f = figure('Name','WORKING DataTip Tool - Use different mouse buttons!', ...
    'Position', [100 100 1000 700]);
ax = axes('Parent',f, 'Position', [0.1 0.25 0.8 0.65]);

% Create test data with known intersections
t = linspace(0, 4*pi, 200);
plot(ax, t, sin(t), 'b-', 'LineWidth', 2, 'DisplayName', 'sin(t)'); 
hold(ax,'on');
plot(ax, t, cos(t), 'r-', 'LineWidth', 2, 'DisplayName', 'cos(t)');
plot(ax, t, 0.5*ones(size(t)), 'g--', 'LineWidth', 1, 'DisplayName', 'y=0.5');
plot(ax, pi*ones(size(t)), linspace(-1.5, 1.5, length(t)), 'm--', 'LineWidth', 1, 'DisplayName', 'x=π');

grid(ax,'on');
xlabel(ax,'t'); ylabel(ax,'y');
title(ax,'Try different mouse buttons to draw lines and create datatips');
legend(ax, 'Location', 'best');

% Add comprehensive instructions
uicontrol('Style','text','Units','normalized','Position',[0.05 0.02 0.9 0.2], ...
    'String', sprintf(['MOUSE BUTTON CONTROLS:\n\n' ...
    '- LEFT CLICK + DRAG = Free line (red, follows mouse exactly)\n' ...
    '-  RIGHT CLICK + DRAG = Horizontal line (orange, fixed Y-coordinate)\n' ...  
    '-  MIDDLE CLICK + DRAG = Vertical line (blue, fixed X-coordinate)\n' ...
    '-  CTRL + DRAG = X-axis datatips at y=0 (any click type)']), ...
    'FontSize', 10, 'HorizontalAlignment', 'left', 'FontWeight', 'normal');

% Create the tool
addpath(fileparts(mfilename('fullpath')));
tool = InteractiveDataTipTool(ax);
tool.setEnabled(true);

fprintf('DEMO IS READY!\n\n');
fprintf('The plot shows sin(t), cos(t), and reference lines.\n');
fprintf('Try drawing lines that intersect these curves:\n\n');
fprintf('1.  LEFT click + drag = Free line (any angle)\n');
fprintf('2.  RIGHT click + drag = Horizontal line (will intersect at specific Y values)\n');
fprintf('3.  MIDDLE click + drag = Vertical line (will intersect at specific X values)\n\n');
fprintf('Close the figure when you''re done testing.\n\n');

% Wait for figure to close
waitfor(f);
fprintf('\n Demo completed successfully!\n');
end
