# Survey-aware ML Analysis: Public Release

This folder is a minimal public package for the accepted paper. It includes:

- curated analysis inputs in `data/`
- public `R` scripts for preprocessing and Experiments `1-4` in `code/`
- reproducibility notebooks in `notebooks/repro/`
- expected baseline fixtures in `expected/` for PASS/FAIL checks

It does not include the internal manuscript workspace, audit tooling, or the full internal result/output tree.

## Runtime

The supported runtime is `conda` environment `rlab`.

```bash
conda env create -f environment.yml
conda activate rlab
```

`environment.yml` includes the packages required for the accepted-paper Experiments `1-4`, including `xgboost`.

`pdftoppm` is required for figure checks and is provided through `poppler` in `environment.yml`.

### Optional: rerun preprocessing from raw NHANES

`code/00_preprocessing.R` is **not** needed to reproduce the accepted-paper results. It is included only for provenance and follow-up preprocessing checks. If you plan to rerun it, install `nhanesA` separately:

```bash
Rscript -e "install.packages('nhanesA', repos='https://cloud.r-project.org')"
```

This optional step requires internet access during preprocessing.

## Folder Layout

```text
saml_repo/
├── code/              # preprocessing + Exp 1-4 scripts
├── data/              # curated RDS inputs used by the paper package
├── expected/          # baseline fixtures used by repro notebooks
├── notebooks/repro/   # rerun + compare notebooks
├── environment.yml
├── LICENSE
└── README.md
```

## Running the Public Scripts

Run commands from the repository root:

```bash
conda run -n rlab Rscript code/01_experiment1_descriptive.R
conda run -n rlab Rscript code/02_experiment2_evaluation.R
conda run -n rlab Rscript code/03_experiment3_training.R
conda run -n rlab Rscript code/04_experiment4_cv_factorial.R
```

Generated outputs are written to `results/`, which is intentionally ignored by git.
Fresh outputs in `results/` can be compared against the frozen `expected/*.rds` fixtures through the reproducibility notebooks.

Approximate runtimes on the audit machine:

- `01_experiment1_descriptive.R`: ~10 seconds
- `02_experiment2_evaluation.R`: ~1 minute
- `03_experiment3_training.R`: ~4 minutes
- `04_experiment4_cv_factorial.R`: ~15-20 minutes

The accepted-paper experiments intentionally use a minimal two-feature model: `age` and `BMI`.

`data/` and `expected/` are the canonical frozen accepted-paper artifacts for this package.

`code/00_preprocessing.R` is included for provenance and follow-up preprocessing. It downloads raw NHANES tables, derives supplementary fields such as `female` and `race_eth`, and writes regenerated artifacts to `results/`; it does not overwrite the curated frozen inputs in `data/`, and those regenerated outputs are not the baseline used for the accepted-paper repro checks.

`Experiment 4` in this package intentionally preserves the accepted-paper cross-validation implementation. This keeps the release numerically aligned with the paper artifacts, even though that implementation should be interpreted as a frozen paper baseline rather than a corrected follow-up benchmark.

## Running the Reproducibility Notebooks

The notebooks rerun the public scripts in an isolated scratch workspace and compare the outputs against `expected/`.

From `notebooks/repro/`, the default one-command verifier is:

```bash
bash verify_all.sh
```

To run a single notebook manually:

```bash
cd notebooks/repro

JUPYTER_CONFIG_DIR=/tmp/empty_jupyter_config \
  conda run -n rlab jupyter nbconvert --to notebook --execute \
  --ExecutePreprocessor.timeout=7200 \
  --ExecutePreprocessor.kernel_name=ir \
  01_exp1_repro.ipynb --output 01_exp1_repro_executed.ipynb
```

Repeat for `02_exp2_repro.ipynb`, `03_exp3_repro.ipynb`, and `04_exp4_repro.ipynb`.

## Notes

- `data/` is the canonical curated input for this release.
- `expected/` contains only the baseline fixtures needed for public reproducibility checks.
- `female` and `race_eth` are follow-up-ready preprocessing fields, not predictors used in the accepted-paper experiments.
- `Exp 5` and the internal portability-audit workflow are intentionally excluded from this package.
- `notebooks/repro/build_repro_notebooks.py` is developer tooling used to regenerate the four repro notebooks; public users do not need to run it for standard verification.

## License and Citation

- `LICENSE` in this folder is a stub. The published repository will use the **GitHub-generated LICENSE** (auto-injected at repo creation), so the in-repo file will be replaced at publication time.
- Author / ORCID / paper citation metadata (`CITATION.cff`, BibTeX) are intentionally **deferred to a later metadata pass**, closer to publication. They are not part of this snapshot.
- NHANES data attribution is tracked separately under `data/README.md` (NHANES source tables, download date, filter chain) and is **not** affected by the LICENSE / CITATION deferral above.
