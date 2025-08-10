function tool = installMouseDataTipsFeature(ax, checkbox)
% installMouseDataTipsFeature Wire up the mouse-based Data Tips feature to your GUI.
%
% Usage:
%   tool = installMouseDataTipsFeature(ax);
%   % or, to bind to a uicontrol checkbox's value:
%   tool = installMouseDataTipsFeature(ax, hCheckbox);
%
% Arguments:
%   ax        - target axes handle.
%   checkbox  - optional uicontrol style 'checkbox' or uicheckbox (uifigure)
%               whose value toggles Enable. If provided, this function will
%               attach a callback so the tool tracks the checkbox state.
%
% Returns:
%   tool      - instance of InteractiveDataTipTool; keep a reference in your GUI
%               handles to avoid being garbage collected.
%
% Mouse Controls:
%   LEFT click + drag   = Free line (follows mouse)
%   RIGHT click + drag  = Horizontal line (fixed Y-coordinate)
%   MIDDLE click + drag = Vertical line (fixed X-coordinate)

if nargin < 1 || ~ishghandle(ax) || ~strcmp(get(ax,'Type'),'axes')
    error('installMouseDataTipsFeature:InvalidAxes', 'Provide a valid axes handle.');
end

% Create tool
try
    tool = InteractiveDataTipTool(ax);
catch ME
    error('installMouseDataTipsFeature:CreationFailed','%s', ME.message);
end

% Hook to checkbox if provided
if nargin >= 2 && ~isempty(checkbox) && ishghandle(checkbox)
    % initialize state from checkbox
    val = getCheckboxValue(checkbox);
    tool.setEnabled(logical(val));

    % attach listener
    if isprop(checkbox,'ValueChangedFcn')
        checkbox.ValueChangedFcn = @(src,~) onToggle(tool, getCheckboxValue(src));
    else
        set(checkbox, 'Callback', @(src,~) onToggle(tool, getCheckboxValue(src)));
    end
end

    function onToggle(toolObj, v)
        toolObj.setEnabled(v);
    end

    function v = getCheckboxValue(h)
        v = get(h,'Value');
    end
end
