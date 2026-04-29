# `data/` provenance for the frozen SaML public release

This folder contains the curated, frozen accepted-paper inputs used by the public SaML package.

## Files

- `nhanes_processed.rds`
  - Adult NHANES 2021-2023 analytic cohort derived from public-use source tables.
  - Includes the accepted-paper outcome fields and supplementary follow-up demographic fields used by later studies.
- `survey_design.rds`
  - `survey::svydesign` object built from `nhanes_processed.rds` using `SDMVPSU`, `SDMVSTRA`, and `WTMEC2YR`.
- `model_df.rds`
  - Frozen complete-case accepted-paper modeling input for the minimal two-feature baseline (`RIDAGEYR`, `BMXBMI`).

## Source tables

The shipped RDS files were derived from the following NHANES 2021-2023 public-use files:

- `DEMO_L` — demographics and survey design
- `BMX_L` — body measures
- `BPXO_L` — oscillometric blood pressure
- `DIQ_L` — diabetes questionnaire

These are the same public tables downloaded by `code/00_preprocessing.R` through `nhanesA::nhanes()`.

## Filter chain

The frozen cohort is based on the following release preprocessing rules:

- keep rows with `WTMEC2YR > 0`
- keep adults with `RIDAGEYR >= 20`
- derive the accepted-paper diabetes outcome from `DIQ010`
- derive the accepted-paper hypertension outcome from `BPXOSY1` / `BPXODI1`
- construct `model_df.rds` as the complete-case minimal accepted-paper modeling slice

## Usage notes

- `data/` is the canonical input for reproducing the accepted-paper Experiments `1-4`.
- `code/00_preprocessing.R` writes regenerated follow-up-ready artifacts to `results/`; it does **not** overwrite the frozen `data/` files in this folder.
- The accepted-paper package intentionally remains aligned to the minimal two-feature baseline (`age` and `BMI`), even though `nhanes_processed.rds` carries supplementary demographic fields for follow-up studies.

## Attribution

These files are derived from publicly released NHANES data produced by the U.S. Centers for Disease Control and Prevention, National Center for Health Statistics.

When reusing or redistributing derived outputs from this package, cite:

- the specific NHANES 2021-2023 public-use source tables listed above
- the NHANES program website / documentation used for access
- this SaML package or paper once repository citation metadata is added

Project-level author metadata and `CITATION.cff` are intentionally deferred to a later publication metadata pass. That deferral does **not** change the NHANES attribution expectations for the derived files in this folder.
