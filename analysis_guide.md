# Analysis Guide

This local paper factory uses **Python** as its analysis language for every step of the pipeline. There is no Stata, no Slurm, and no `module load`. All analysis code lives under `code/`, all logs land in `logs/`, and analysis-ready datasets live under `data/final/` (with intermediate staging under `data/intermediate/`).

## Python Environment

A working interpreter is required on `PATH`. The factory will use `python3` by default. Override with the `PYTHON_BIN` environment variable to point at a `uv`, `conda`, or `virtualenv` interpreter:

```bash
export PYTHON_BIN=/path/to/.venv/bin/python
```

### Recommended Libraries

The pipeline assumes the standard quantitative-Python stack is available:

| Purpose | Library |
|---------|---------|
| Data manipulation | `pandas`, `numpy`, `pyarrow` |
| Tabular I/O (parquet, feather, csv) | `pandas` + `pyarrow` |
| Regression / inference | `statsmodels`, `linearmodels`, `pyfixest` |
| Causal designs (IV, panel FE, DiD) | `linearmodels`, `pyfixest`, `differences` |
| Statistical tests | `scipy.stats` |
| Plotting | `matplotlib` (canonical) |
| LaTeX regression tables | `stargazer`, or hand-rolled with `to_latex()` |
| Survey weights / complex designs | `statsmodels` GEE, `samplics`, or manual weighting |

Install with `pip install pandas numpy pyarrow statsmodels linearmodels pyfixest matplotlib scipy stargazer` or via `uv pip install ...`.

## Local Python Execution

The factory does not use Slurm. It provides a small wrapper, `python_submit.sh`, that launches a Python script as a local background process and returns a local job id.

From a project directory under `ongoing/` or `complete/`, use:

```bash
PYTHON_SUBMIT="../../python_submit.sh"
JOBID=$("$PYTHON_SUBMIT" code/filename.py)
echo "Submitted local Python job $JOBID"
```

Check status:

```bash
"$PYTHON_SUBMIT" --status "$JOBID"
```

Wait for completion:

```bash
"$PYTHON_SUBMIT" --wait "$JOBID"
```

Important rules:
- Do not call `sbatch`, `srun`, `sacct`, or `module load`.
- Do not pipe code into a Python REPL. Always submit a self-contained `.py` file via `python_submit.sh`, or run it directly with `python3 code/file.py > logs/file.log 2>&1`.
- The log appears in `logs/` named after the script (e.g., `code/03_main.py` writes `logs/03_main.log`).
- The wrapper also writes `logs/<name>.exitcode` so downstream code can distinguish clean exits from failures.
- `--time` is accepted for compatibility but is advisory only in local mode.

### Working While Jobs Run

Do not block on one Python job if other work is available. Submit a job, continue writing the next script or reading results, and poll status periodically. The task is not finished until the relevant Python jobs have completed and their logs have been reviewed.

### Parallel Scripts

When multiple scripts are independent and all read from the same built dataset, submit them in parallel:

```bash
PYTHON_SUBMIT="../../python_submit.sh"
JOB1=$("$PYTHON_SUBMIT" code/03_univariate.py)
JOB2=$("$PYTHON_SUBMIT" code/04_bivariate.py)
JOB3=$("$PYTHON_SUBMIT" code/05_trends.py)
echo "Jobs: $JOB1 $JOB2 $JOB3"
```

Each sibling script must load the analysis dataset independently. Do not assume shared in-memory state across local background jobs.

## Local LaTeX Compilation

Use the local compile helper instead of `module load`:

```bash
../../compile_paper.sh "$(pwd)" your_base_name
```

This runs `pdflatex`, `bibtex` when needed, then two more `pdflatex` passes.

## Figure Style Specification

All figures must follow this style. Use `matplotlib`; configure once via `rcParams` and reuse across scripts.

### Canvas and Export
- Export format: vector PDF
- Page size: 540 x 324 pt (7.5 x 4.5 in, 5:3 aspect ratio) — `plt.figure(figsize=(7.5, 4.5))`
- Background: white (`#FFFFFF`)

### Color Palette
| Role | Color | RGB |
|------|-------|-----|
| Primary fill (bars, CIs, error bars, main series) | Blue `#1A85FF` | 26, 133, 255 |
| Secondary fill / point estimates / markers | Magenta `#D41159` | 212, 17, 89 |
| Low-density dashed line | Dark magenta `#C10534` | 193, 5, 52 |
| Grid lines | Light gray `#F0F0F0` | 240, 240, 240 |
| Zero reference line | Gray `#A0A0A0` | 160, 160, 160 |
| Event-time reference line | Red `#FF0000` | 255, 0, 0 |

Color usage rules:
- Single-series bar charts: use Blue `#1A85FF`.
- Two-series bar charts: use Blue `#1A85FF` for the first series and Magenta `#D41159` for the second.
- Coefficient/dot plots: use Magenta `#D41159` for point estimates and Blue `#1A85FF` for confidence intervals.
- Line plots: use Blue `#1A85FF` (solid) for the first series and Dark magenta `#C10534` (dashed) for the second.
- Do not use colors outside this palette.

### Typography
- Font: Helvetica (fallback: Arial) — set `rcParams['font.family'] = ['Helvetica', 'Arial', 'sans-serif']`
- Axis labels, tick labels, legend text: about 17 pt
- Title (if used): about 19 pt, centered
- Numeric style: `.05`, `-.05`, `0`

### Axes and Grid
- Show left and bottom axes in black; hide top and right spines (`ax.spines['top'].set_visible(False)`, same for `'right'`).
- Axis/tick stroke: about 0.65 pt
- Major gridlines only: dashed, `#F0F0F0`, about 1 pt (`ax.grid(True, which='major', linestyle='--', linewidth=1.0, color='#F0F0F0')`)
- Horizontal zero line when relevant: `#A0A0A0`, dashed (`ax.axhline(0, color='#A0A0A0', linestyle='--')`)
- Vertical event marker at treatment cutoff: `#FF0000`, dashed, at x = -0.5 (`ax.axvline(-0.5, color='#FF0000', linestyle='--')`)

### Important Figure Rules
- All explanatory notes go in LaTeX `\note{}`, not in the figure graphic.
- Do not call `plt.title()` or set figure-level titles, captions, or notes inside `matplotlib`. Panel labels via subplots are fine; everything else goes in the LaTeX `\note{}` field.
- Always save as PDF: `plt.savefig('figures/fig_name.pdf', bbox_inches='tight')`.

### Reusable Style Snippet

Drop this near the top of every figure script:

```python
import matplotlib as mpl
import matplotlib.pyplot as plt

mpl.rcParams.update({
    'font.family': ['Helvetica', 'Arial', 'sans-serif'],
    'font.size': 17,
    'axes.spines.top': False,
    'axes.spines.right': False,
    'axes.linewidth': 0.65,
    'xtick.major.width': 0.65,
    'ytick.major.width': 0.65,
    'grid.color': '#F0F0F0',
    'grid.linestyle': '--',
    'grid.linewidth': 1.0,
    'axes.grid': True,
    'pdf.fonttype': 42,  # embed fonts as TrueType (editable in Illustrator)
    'ps.fonttype': 42,
})

PAL = {
    'blue':       '#1A85FF',
    'magenta':    '#D41159',
    'darkmag':    '#C10534',
    'gray':       '#A0A0A0',
    'gridgray':   '#F0F0F0',
    'eventred':   '#FF0000',
}
```

## Data Layout and Cleanup

Use a consistent storage layout so delivery can safely prune rebuildable data.

- `data/raw/`: downloaded or original source artifacts only
- `data/intermediate/`: rebuildable staged products
- `data/final/`: rebuildable analysis-ready datasets
- `tmp/` and `replication/temp/`: scratch space only

Legacy projects may already use `analysis/raw*`, `analysis/intermediate`, `analysis/final`, or `analysis/unified`. If that layout already exists, keep it internally consistent; otherwise use the `data/raw`, `data/intermediate`, `data/final` structure above.

Hard rules:
- Keep source artifacts separate from rebuildable outputs.
- Do not save rebuildable analysis datasets in the project root.
- If a file can be recreated from source artifacts plus scripts, it belongs in `data/intermediate/`, `data/final/`, or the analogous legacy `analysis/` directory.

### Preferred Data Formats

- **Analysis-ready datasets**: `.parquet` (preferred — fast, typed, compressed) or `.feather`. Load with `pd.read_parquet(...)`.
- **Human-inspectable extracts**: `.csv` or `.csv.gz`. Avoid for large analysis datasets.
- **Source artifacts**: leave in their original format under `data/raw/` (no conversion just for convenience).

Do not use Stata `.dta` files for new outputs. If the project inherits `.dta` files in `data/raw/`, read them once with `pd.read_stata(...)`, immediately rewrite to `.parquet` in `data/intermediate/`, and work from the parquet thereafter.

## Script Conventions

Use a small project-config block at the top of each script so paths stay consistent:

```python
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
DATA = PROJECT / "data"
RAW = DATA / "raw"
INTERMEDIATE = DATA / "intermediate"
FINAL = DATA / "final"
FIGURES = PROJECT / "figures"
TABLES = PROJECT / "tables"
LOGS = PROJECT / "logs"
```

### Script Naming

Organize active scripts by purpose:
- `code/01_explore.py`
- `code/02_descriptive.py`
- `code/03_main_analysis.py`
- `code/04_figures.py`
- `code/05_heterogeneity.py`
- `code/06_mechanisms.py`
- `code/07_robustness.py`

Step-specific prompts may impose stricter prefixes such as `desc_`, `f1_`, or `ext1_`. Follow the prompt when it is more specific than this general scheme.

### Logging

Every script must produce a log file in `logs/` with the same base name as the script. Two equivalent options:

**Option A (recommended): let `python_submit.sh` capture stdout/stderr.** Just `print()` everything you would normally `display` in Stata. The wrapper redirects to `logs/<name>.log`.

**Option B: use the `logging` module.** Useful when you want structured records:

```python
import logging
from pathlib import Path

LOG = Path(__file__).resolve().parents[1] / "logs" / (Path(__file__).stem + ".log")
LOG.parent.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    filename=LOG,
    filemode='w',
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
)
```

Whichever you pick, the log must contain: the dataset path loaded, sample sizes after each restriction, the regression specifications run, and the printed coefficients with standard errors.

### Python Error Recovery

When a script fails:
1. Read the log immediately (`logs/<name>.log`).
2. Diagnose the root cause (read the traceback).
3. Fix the script and re-run it.
4. If a package is missing, install it with `pip install <pkg>` (or `uv pip install <pkg>`) and re-run.

### Regression Table Formatting

Generate clean LaTeX regression tables from the start. Two approved approaches:

**Approach 1: `stargazer` (closest to `esttab`)**

```python
from stargazer.stargazer import Stargazer

models = [m1, m2, m3, m4]
sg = Stargazer(models)
sg.title("")
sg.show_model_numbers(True)
sg.significance_levels([0.05, 0.01, 0.001])
sg.significant_digits(3)
sg.show_degrees_of_freedom(False)
sg.rename_covariates({
    "treat": "Treatment",
    "post": "Post",
    "treat:post": "Treatment $\\times$ Post",
})
sg.add_line("Year FE", ["Yes", "Yes", "Yes", "Yes"])
sg.add_line("Industry FE", ["No", "Yes", "Yes", "Yes"])
with open(TABLES / "tab_main.tex", "w") as f:
    f.write(sg.render_latex(only_tabular=True))
```

**Approach 2: hand-rolled via `pandas.DataFrame.to_latex(escape=False)`**

Use for summary statistics, balance tables, descriptive comparisons. Always pass `escape=False` so LaTeX math survives, and write to `tables/<name>.tex`.

Key rules:
- Always rename raw variable names to readable labels (use `rename_covariates(...)` or build a label dictionary).
- Use `only_tabular=True` (or write just the `tabular` block) so the paper controls the `table` environment and caption.
- Use `booktabs` style (`\toprule`, `\midrule`, `\bottomrule`). Both `stargazer` and `to_latex()` support this.
- Read the generated `.tex` and remove duplicate header rows or notes if needed.

### Common Stata-to-Python Translation Cheatsheet

| Stata | Python |
|-------|--------|
| `use file.dta, clear` | `df = pd.read_parquet('file.parquet')` |
| `describe`, `codebook` | `df.info()`, `df.describe(include='all')` |
| `summarize var, detail` | `df['var'].describe(percentiles=[.1,.25,.5,.75,.9])` |
| `tabulate var` | `df['var'].value_counts(dropna=False)` |
| `tabulate v1 v2` | `pd.crosstab(df['v1'], df['v2'])` |
| `gen y = log(x)` | `df['y'] = np.log(df['x'])` |
| `egen mean_x = mean(x), by(g)` | `df['mean_x'] = df.groupby('g')['x'].transform('mean')` |
| `keep if year >= 2000` | `df = df.loc[df['year'] >= 2000]` |
| `merge 1:1 id using ...` | `df = df.merge(other, on='id', how='inner', validate='1:1')` |
| `reg y x controls, cluster(id)` | `smf.ols('y ~ x + c1 + c2', data=df).fit(cov_type='cluster', cov_kwds={'groups': df['id']})` |
| `reghdfe y x, absorb(i.id i.year)` | `pyfixest.feols('y ~ x \| id + year', data=df)` |
| `xtreg y x, fe vce(cluster id)` | `linearmodels.PanelOLS(...).fit(cov_type='clustered', cluster_entity=True)` |
| `ivregress 2sls y (x = z) controls` | `linearmodels.IV2SLS.from_formula('y ~ 1 + controls + [x ~ z]', data=df).fit()` |
| `event-study via reghdfe` | `pyfixest.feols('y ~ i(event_t, ref=-1) \| id + t', data=df)` |
| `esttab m1 m2 using out.tex, ...` | `Stargazer([m1, m2]).render_latex(only_tabular=True)` |
| `graph export fig.pdf` | `plt.savefig('figures/fig.pdf', bbox_inches='tight')` |
