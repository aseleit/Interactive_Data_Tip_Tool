function demo_standalone()
clc; fprintf(['Draw lines to create datatips.\n' ...
              'In the Aligner: tick X or Y on two rows (first=mover, second=target).\n' ...
              'Click "Save CSV" to export SignalName, Index, X, Y.\n']);

f = figure('Name','DataTip Tool + Aligner','Position',[100 100 1000 700]);
ax = axes('Parent',f,'Position',[0.10 0.25 0.80 0.65]);

t = linspace(0,4*pi,200);
plot(ax, t, sin(t), 'b-o', 'LineWidth', 2, 'DisplayName', 'sin(t)'); hold(ax,'on');
plot(ax, t, cos(t), 'r-*', 'LineWidth', 2, 'DisplayName', 'cos(t)');
plot(ax, t, 0.5*ones(size(t)), 'g--', 'LineWidth', 1, 'DisplayName', 'y=0.5');
plot(ax, pi*ones(size(t)), linspace(-1.5,1.5,length(t)), 'm--', 'LineWidth', 1, 'DisplayName', 'x=\pi');
grid(ax,'on'); xlabel(ax,'t'); ylabel(ax,'y');
title(ax,'Draw lines to create datatips. Use the Aligner window to align.'); legend(ax,'Location','best');

tool = InteractiveDataTipTool(ax);
tool.setEnabled(true);
tool.openAligner('Position',[1150 120 560 340]);
end
