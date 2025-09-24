>> DataTipResults
# Interactive DataTip Tool

Interactive MATLAB tool to create and manage DataTips on figures using mouse-driven drawing and a standalone "DataTip Aligner" GUI for inspection and alignment.

## Features

- Mouse-driven line drawing with constraint modes (free, horizontal, vertical)
- Visual line preview while dragging and automatic datatip creation at intersections
- Standalone "DataTip Aligner" GUI with a table listing created datatips
   - Select checkboxes for signal operations
   - Move X/Move Y checkboxes for alignment operations
- Workspace saving to `DataTipResults` variable and timestamped CSV export
- Easy GUI integration via `installMouseDataTipsFeature`
- Enhanced move logging with signal names and movement descriptions

## Files Included

- `InteractiveDataTipTool.m` - Main tool class (creates datatips and the DataTip Aligner GUI)
- `installMouseDataTipsFeature.m` - Helper for GUIDE/App-Designer integration
- `demo.m` / `demo_standalone.m` - Demo scripts (open the GUI and show usage)
- `README.md` - This file

## Quick Start

```matlab
% Add to path
addpath('/path/to/Interactive_Data_Tip_Tool')

% Run the demo (opens the figure and the DataTip Aligner GUI)
demo
```

## DataTip Aligner (Standalone GUI)

The DataTip Aligner window lists all created datatips in a table with these columns: 
- **Select** - Checkbox to select signals for various operations
- **Signal Name** - Name of the intersected line
- **X** - X-coordinate of the data tip
- **Move X** - Checkbox to select this tip for X-alignment
- **Y** - Y-coordinate of the data tip  
- **Move Y** - Checkbox to select this tip for Y-alignment

### Selection and Alignment Operations

- **Select All Button**: Click "Select All" to toggle selection of all signals at once
- **Move X/Move Y Alignment**: Check Move X or Move Y boxes for exactly two tips to enable alignment operations. The first checked box becomes the mover, the second becomes the target. Same-curve selections result in no operation.
- **Snap Selected**: Select signals using Select checkboxes, enter Target X/Y coordinates, then click "Snap Selected" to move all selected signals to that point
- **Export Operations**: Use "Send Selected to WS" or "Save Selected to CSV" to work with only the selected signals

### Move Log

The Delta Log column displays detailed movement information in the format:
"[Signal Name] moved +/-[value] on X-axis" or "[Signal Name] moved +/-[value] on Y-axis"

This provides clear tracking of which signals were moved and by how much.

### Button Functions

- **Refresh**: Update the table and remove deleted data tips
- **Reset**: Restore all modified lines to their original positions
- **Send All to Workspace**: Export all results to MATLAB workspace variable "DataTipResults"
- **Send Selected to WS**: Export only selected tips to workspace variable "SelectedDataTipResults"  
- **Save All to CSV**: Export all data tips to a CSV file
- **Save Selected to CSV**: Export only selected data tips to a CSV file
- **Help**: Show comprehensive help dialog with README access

Example: To align one signal tip to another signal tip, check both Move X boxes (first = mover, second = target) and the alignment will occur automatically.

## GUI Integration

### GUIDE-style GUIs
```matlab
% In your GUI opening function:
addpath('/path/to/Interactive_Data_Tip_Tool')
handles.dataTipTool = installMouseDataTipsFeature(handles.axes1);
% Optionally store a checkbox handle to toggle the feature
guidata(hObject, handles);
```

### App Designer
```matlab
% In startupFcn:
addpath('/path/to/Interactive_Data_Tip_Tool')
app.DataTipTool = installMouseDataTipsFeature(app.UIAxes);
```

### Manual Setup (script)
```matlab
f = figure;
ax = axes('Parent', f);
plot(ax, 1:100, sin(linspace(0,10,100)));

tool = InteractiveDataTipTool(ax);
tool.setEnabled(true);
% Optional: open the standalone aligner GUI
tool.openGUI();
```

## Data Export

Results are saved to the base workspace variable `DataTipResults`:

```matlab
>> DataTipResults
ans = 
   struct array with fields:
      SignalName     % Name of the intersected line
      Index          % Index of the nearest vertex
      X              % X-coordinate of datatip
      Y              % Y-coordinate of datatip
```

CSV export behavior:
- Format: User-specified filename
- Contains: SignalName, Index, X, Y columns
- Supports both "Save All" and "Save Selected" operations

## Mouse Controls (summary)

| Input | Constraint | Notes |
|-------|------------|-------|
| Left click + drag | Free | Draw free line and create datatips at intersections |
| Right click + drag | Horizontal | Y locked to start point |
| Middle click + drag | Vertical | X locked to start point |
| Ctrl+Click + drag | X-Axis Constrained | Creates datatips only at Y=0 crossings |

## Example Workflow

1. Launch the demo: `demo_standalone`
2. Draw lines on the figure to create datatips at intersections
3. Open the "DataTip Aligner" (opens automatically with the demo)
4. Use Select checkboxes to choose signals for operations
5. Use Move X/Move Y checkboxes for alignment (first = mover, second = target)
6. Review detailed movement logs in the Delta Log column
7. Export results using workspace or CSV export options

## Troubleshooting

- If alignment operations don't work, ensure exactly two tips are selected with Move X or Move Y checkboxes
- If values appear incorrect, press "Refresh" to update the table
- Use "Reset" to restore all signals to their original positions
- Select All button helps quickly select/deselect all signals for batch operations
