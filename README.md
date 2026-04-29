# SaML Public Reproduction Package

This package reproduces the public experimental results for the SaML paper using
curated NHANES-derived inputs shipped in `data/`.

It includes:

- public R scripts for Experiments 1-4
- frozen input data used by the release
- expected result fixtures for verification
- reproducibility notebooks and a one-command verification script

## Quick Start

Create the environment:

```bash
conda env create -f environment.yml
```

Run the released experiments from the repository root:

```bash
conda run -n rlab Rscript code/01_experiment1_descriptive.R
conda run -n rlab Rscript code/02_experiment2_evaluation.R
conda run -n rlab Rscript code/03_experiment3_training.R
conda run -n rlab Rscript code/04_experiment4_cv_factorial.R
```

Fresh outputs are written to `results/`.

Approximate runtimes on the audit machine:

- Experiment 1: ~10 seconds
- Experiment 2: ~1 minute
- Experiment 3: ~4 minutes
- Experiment 4: ~15-20 minutes

## Verify the Release

From `notebooks/repro/`, run:

```bash
bash verify_all.sh
```

This executes all four reproducibility notebooks and checks regenerated outputs
against the frozen fixtures in `expected/`.

## Repository Layout

```text
saml_repo/
├── code/              # public preprocessing + Experiment 1-4 scripts
├── data/              # frozen curated release inputs
├── expected/          # frozen baseline result fixtures
├── notebooks/repro/   # reproducibility notebooks and verifier
├── environment.yml    # conda environment
├── LICENSE
└── README.md
```

## What Each Script Does

- `code/01_experiment1_descriptive.R`
  - weighted vs unweighted descriptive summaries
- `code/02_experiment2_evaluation.R`
  - logistic regression with unweighted and survey-weighted AUC evaluation
- `code/03_experiment3_training.R`
  - 2x2 training/evaluation factorial with XGBoost
- `code/04_experiment4_cv_factorial.R`
  - cross-validation factorial benchmark

## Notes on the Data

- `data/` is the canonical frozen input for this release.
- The released experiments use the minimal accepted-paper modeling setup based on
  `RIDAGEYR` and `BMXBMI`.
- Additional demographic fields may appear in the shipped data because the
  release preserves the preprocessing lineage of the public package.

See [data/README.md](data/README.md) for source tables, filter rules, and
attribution notes for the derived NHANES inputs.

## Optional: Rebuild Preprocessing Inputs

`code/00_preprocessing.R` is included for provenance and data-regeneration
checks. It is **not** required for reproducing Experiments 1-4 from the shipped
release.

If you want to rerun preprocessing from raw NHANES tables, install `nhanesA`
separately:

```bash
Rscript -e "install.packages('nhanesA', repos='https://cloud.r-project.org')"
```

This step requires internet access.

## Developer Note

`notebooks/repro/build_repro_notebooks.py` regenerates the reproducibility
notebooks. It is not needed for standard use of the public release.
