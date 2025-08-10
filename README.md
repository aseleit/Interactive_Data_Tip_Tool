# Interactive DataTip Tool - Mouse Button Version

This is the final, working version of the DataTip line drawing tool that uses mouse buttons for constraints instead of keyboard keys. This approach is much more reliable across all MATLAB versions and platforms.

## Features

 **Mouse button constraints** (no keyboard issues!)  
 **Ctrl modifier for x-axis datatips** at y=0  
 **Visual line preview** while dragging  
 **Automatic datatip creation** at intersections  
 **Workspace saving** to `DataTipResults` variable  
 **CSV export** with timestamps  
 **GUI integration** support  

## Files Included

- `InteractiveDataTipTool.m` - Main tool class
- `installMouseDataTipsFeature.m` - Helper for GUI integration  
- `final_working_demo.m` - Complete demo with test data
- `README.md` - This file

## Quick Start

```matlab
% Add to path
addpath('/path/to/final_datatip_tool')

% Run the demo
final_working_demo
```

## Mouse Controls

| Input | Constraint | Line Color | Description |
|-------|------------|------------|-------------|
| **LEFT** click + drag | Free | Red | Line follows mouse exactly |
| **RIGHT** click + drag | Horizontal | Orange | Y-coordinate locked to start point |
| **MIDDLE** click + drag | Vertical | Blue | X-coordinate locked to start point |
| **CTRL** + drag | X-axis only | Red | Creates datatips only at y=0 crossings |

### Mac Users
- **Ctrl+Click** = Right-click
- **Two-finger click** = Right-click  
- **Three-finger click** or **Shift+Click** = Middle-click

## Data Export

### Workspace
Results are automatically saved to the base workspace variable `DataTipResults`:
```matlab
>> DataTipResults
ans = 
  struct array with fields:
    x              % X-coordinate of datatip
    y              % Y-coordinate of datatip  
    line_name      % Name of the intersected line
    constraint_mode % 'free', 'horizontal', or 'vertical'
```

### CSV Export
Each drawing session creates a timestamped CSV file in the current directory:
- Format: `datatip_results_YYYY-MM-DD_HH-MM-SS.csv`
- Contains: x, y, line_name, constraint_mode columns
- Can be opened in Excel or other data analysis tools

## GUI Integration

### GUIDE-style GUIs
```matlab
% In your GUI opening function:
addpath('/path/to/final_datatip_tool')
handles.dataTipTool = installMouseDataTipsFeature(handles.axes1, handles.chkDataTips);
guidata(hObject, handles);
```

### App Designer
```matlab  
% In startupFcn:
addpath('/path/to/final_datatip_tool')
app.DataTipTool = installMouseDataTipsFeature(app.UIAxes, app.DataTipsCheckBox);
```

### Manual Setup
```matlab
% Create your figure and axes
f = figure;
ax = axes('Parent', f);
plot(ax, 1:10, sin(1:10), 'b-');

% Add the tool
tool = InteractiveDataTipTool(ax);
tool.setEnabled(true);
```

## Example Usage

1. **Run the demo**: `final_working_demo`
2. **Try different mouse buttons**:
   - Left-click + drag for free lines
   - Right-click + drag for horizontal lines  
   - Middle-click + drag for vertical lines
3. **Check results**:
   - Console shows real-time feedback
   - Workspace variable `DataTipResults` contains all data
   - CSV file created in current directory

## Advantages Over Keyboard Version

-  **100% reliable** - no keyboard event timing issues
-  **Cross-platform** - works on all MATLAB versions  
-  **No focus issues** - mouse events always work
-  **Visual feedback** - different colors for different modes
-  **Intuitive** - right-click for horizontal feels natural

## Requirements

- MATLAB R2016b or later (for `datatip` function)
- For older versions, falls back to console output
- Works with both `figure` and `uifigure` (App Designer)

## Troubleshooting

**Preview line not appearing**: Ensure you're clicking within the target axes area.

**No datatips created**: Verify your drawn line actually intersects with visible line objects in the axes.

**CSV export fails**: Check that you have write permissions in the current directory.

**Mouse buttons not working**: Try the alternatives mentioned in the Mac Users section above.
