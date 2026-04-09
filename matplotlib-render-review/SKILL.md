---
name: matplotlib-render-review
description: "Render-Review-Refine workflow for matplotlib charts. Visual feedback loop using Claude Code's multimodal Read tool."
paths: "**/*.py,**/*.ipynb"
---

# Matplotlib Render-Review-Refine Workflow

Claude Code is multimodal -- it can see rendered PNGs via the `Read` tool. Use this
to close a visual feedback loop: generate chart code, render to PNG, Read the PNG,
review what you see, and iterate.

---

## Section 1: Render-Review-Refine Workflow

Every chart task follows one of two workflows. Both end with visual verification.

### Workflow A -- New Chart from Scratch

1. **Write** chart code as a standalone `.py` script that:
   - Reads the `CHART_OUTPUT` env var for the output path
     (`os.environ.get("CHART_OUTPUT", "/tmp/chart_review.png")`)
   - Uses OOP Figure API: `Figure()` + `FigureCanvasAgg(fig)` + `fig.savefig()`
   - Constructs minimal test data inline OR imports from the project
2. **Render** via the harness:
   ```bash
   python ${CLAUDE_SKILL_DIR}/scripts/render_review.py /tmp/my_chart.py --output /tmp/my_chart.png
   ```
3. **Read the PNG** with the `Read` tool to visually inspect the result.
4. **Apply** the Self-Review Checklist (Section 2).
5. **Fix and re-render** if issues found (max 2 additional cycles).
6. **Integrate** the chart code into the target module. Clean up temp files.

### Workflow B -- Modify Existing Chart Code

1. **Read** the existing rendering function in the target module.
2. **Make** the change directly in the target file.
3. **Write** a minimal test harness script to `/tmp/` that imports the modified
   code and renders a representative case with realistic data.
4. **Render** via the harness, **Read the PNG**, apply checklist.
5. **Fix and re-render** if issues found (max 2 additional cycles).
6. **Clean up** temp files.

### Workflow Rules

- **Maximum 3 total render cycles** (initial + 2 refinements). If issues remain
  after 3 cycles, report what is still wrong to the user and stop.
- **Always clean up** `/tmp/chart_*.py` and `/tmp/chart_*.png` files when done.
- **DPI: 150** for all renders (good balance of detail and file size). Lower DPI
  loses review detail.
- The render harness passes `CHART_OUTPUT` env var to the script -- always read it
  with `os.environ.get("CHART_OUTPUT", "/tmp/chart_review.png")`.

---

## Section 2: Self-Review Checklist

After every `Read` of a rendered PNG, check these items before deciding whether
to iterate or accept.

### Layout and Spacing

- Panels are not overlapping or clipping into each other
- Title is visible and not cut off by the figure boundary
- All axis labels are fully readable (not truncated or overlapping)
- Legend (if present) does not obscure data
- Sufficient padding between subplots (no label collisions)

### Data Correctness -- Line Plots

- Lines track the expected trend (increasing, decreasing, or flat as expected)
- No unexpected gaps or discontinuities in the line
- Multiple lines are distinguishable from each other
- Data points fall within the expected value range

### Data Correctness -- Bar Charts

- Bar heights are proportional to the underlying data values
- Bars are not clipped at the top or bottom of the axes
- Grouped/stacked bars align correctly with their categories
- Bar labels (if present) match their corresponding values

### Data Correctness -- Scatter Plots

- Points appear at the correct (x, y) positions
- Point sizes and colors (if mapped to data) vary as expected
- No points are hidden behind others without transparency or jitter
- Outliers are visible and not clipped by axis limits

### Data Correctness -- Heatmaps

- Color gradient maps to values in the correct direction
- NaN or missing cells are visually distinct (transparent or hatched)
- Row and column labels are readable, not squeezed or overlapping
- Colorbar is present and labeled with units

### Color and Contrast

- Distinct data series use clearly distinguishable colors
- Grid lines are subtle (alpha ~0.3), not competing with data
- Text is readable against the background
- Color choices work for common forms of color blindness (avoid red/green only)

### Axes

- Axis labels describe the data with units where appropriate
- Tick labels are formatted for readability (K/M/B suffixes for large numbers,
  appropriate date formats for time series)
- No axis is entirely blank when data was expected
- Shared axes are properly aligned across panels

---

## Section 3: Figure Creation Quick Reference

The 3-line idiom for every chart (OOP API, no pyplot):

```python
from matplotlib.figure import Figure
from matplotlib.backends.backend_agg import FigureCanvasAgg

fig: Figure = Figure(figsize=(12, 8))
FigureCanvasAgg(fig)  # Required for fig.savefig() and _repr_png_
# ... add axes, draw data ...
fig.savefig(path, dpi=150, bbox_inches="tight")
```

Standard DPI: **150** for both production and review renders.

For multi-panel layouts, use GridSpec:

```python
import matplotlib.gridspec as gridspec

gs = gridspec.GridSpec(n_rows, 1, figure=fig, height_ratios=ratios, hspace=0.35)
ax_top = fig.add_subplot(gs[0, 0])
ax_bottom = fig.add_subplot(gs[1, 0], sharex=ax_top)
```

---

## Section 4: Render Harness Usage

The render harness script lives at `${CLAUDE_SKILL_DIR}/scripts/render_review.py`.

```bash
# Basic render (output defaults to /tmp/chart_review.png)
python ${CLAUDE_SKILL_DIR}/scripts/render_review.py /tmp/my_chart.py

# Custom output path
python ${CLAUDE_SKILL_DIR}/scripts/render_review.py /tmp/my_chart.py --output /tmp/custom.png

# Render and auto-cleanup the script file
python ${CLAUDE_SKILL_DIR}/scripts/render_review.py /tmp/my_chart.py --cleanup
```

The harness:
- Passes `CHART_OUTPUT` env var to the script with the resolved output path
- Prints the absolute PNG path on success (use this path with the `Read` tool)
- Prints diagnostic stderr on failure
- Returns non-zero exit code on any error

Your chart script should read the output path from the environment:

```python
import os
output_path = os.environ.get("CHART_OUTPUT", "/tmp/chart_review.png")
fig.savefig(output_path, dpi=150, bbox_inches="tight")
```
