# =============================================================================
# 00_preprocessing.R
# NHANES 2021-2023 Data Preprocessing for Survey-aware ML Analysis
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Load Required Packages
# -----------------------------------------------------------------------------

helper_candidates <- c(
  tryCatch(
    file.path(
      dirname(normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = TRUE)),
      "public_paths.R"
    ),
    error = function(e) NA_character_
  ),
  file.path(getwd(), "code", "public_paths.R"),
  file.path(getwd(), "public_paths.R")
)
helper_candidates <- helper_candidates[!is.na(helper_candidates) & file.exists(helper_candidates)]
if (length(helper_candidates) == 0) {
  stop("Could not locate code/public_paths.R.")
}
source(helper_candidates[[1]])

library(survey)
library(nhanesA)
library(tidyverse)

cat("Packages loaded.\n")

# -----------------------------------------------------------------------------
# 2. Download NHANES 2021-2023 Data
# -----------------------------------------------------------------------------

cat("Downloading NHANES 2021-2023 data...\n")

demo <- nhanes("DEMO_L")  # Demographics
bmx  <- nhanes("BMX_L")   # Body Measures
bpx  <- nhanes("BPXO_L")  # Blood Pressure (Oscillometric)
diq  <- nhanes("DIQ_L")   # Diabetes Questionnaire

cat("Data download complete.\n")
cat("  DEMO:", nrow(demo), "rows\n")
cat("  BMX: ", nrow(bmx), "rows\n")
cat("  BPX: ", nrow(bpx), "rows\n")
cat("  DIQ: ", nrow(diq), "rows\n")

# -----------------------------------------------------------------------------
# 3. Merge and Filter Data
# -----------------------------------------------------------------------------

df <- demo %>%
  left_join(bmx, by = "SEQN") %>%
  left_join(bpx, by = "SEQN") %>%
  left_join(diq, by = "SEQN") %>%
  filter(
    !is.na(WTMEC2YR),
    WTMEC2YR > 0,
    RIDAGEYR >= 20  # Adults only
  )

cat("\nMerged dataset:", nrow(df), "rows (adults >= 20 with valid weights)\n")

# -----------------------------------------------------------------------------
# 4. Create Outcome Variables
# -----------------------------------------------------------------------------

df <- df %>%
  mutate(
    # Diabetes: Self-reported physician diagnosis
    diabetes = case_when(
      DIQ010 == "Yes" ~ 1,
      DIQ010 == "No"  ~ 0,
      TRUE ~ NA_real_
    ),
    # Hypertension: SBP >= 140 or DBP >= 90 mmHg
    hypertension = case_when(
      BPXOSY1 >= 140 | BPXODI1 >= 90 ~ 1,
      !is.na(BPXOSY1) ~ 0,
      TRUE ~ NA_real_
    )
  )

# -----------------------------------------------------------------------------
# 5. Create Demographic Variables
# -----------------------------------------------------------------------------

df <- df %>%
  mutate(
    # Follow-up demographic fields.
    # The accepted-paper experiments in this package intentionally use only
    # age and BMI; sex and race/ethnicity are retained here for downstream
    # follow-up analyses.
    female = ifelse(as.character(RIAGENDR) == "Female", 1, 0),
    
    # Age groups
    age_group = cut(RIDAGEYR, 
                    breaks = c(20, 40, 60, 80, Inf),
                    labels = c("20-39", "40-59", "60-79", "80+"),
                    right = FALSE),
    
    race_eth = factor(as.character(RIDRETH3),
                      levels = c("Non-Hispanic White",
                                 "Non-Hispanic Black",
                                 "Mexican American",
                                 "Other Hispanic",
                                 "Non-Hispanic Asian",
                                 "Other Race - Including Multi-Racial"),
                      labels = c("NH White", "NH Black", "Mexican American", 
                                 "Other Hispanic", "NH Asian", "Other/Multi"))
  )

# -----------------------------------------------------------------------------
# 6. Create Survey Design Object
# -----------------------------------------------------------------------------

design <- svydesign(
  ids     = ~SDMVPSU,
  strata  = ~SDMVSTRA,
  weights = ~WTMEC2YR,
  nest    = TRUE,
  data    = df
)

cat("\nSurvey design created.\n")
cat("  Strata: ", length(unique(df$SDMVSTRA)), "\n")
cat("  PSUs:   ", length(unique(paste(df$SDMVSTRA, df$SDMVPSU))), "\n")

# -----------------------------------------------------------------------------
# 7. Summary Statistics
# -----------------------------------------------------------------------------

cat("\n=== Analysis Dataset Summary ===\n")
cat("Total observations:      ", nrow(df), "\n")
cat("Diabetes (non-missing):  ", sum(!is.na(df$diabetes)), "\n")
cat("Diabetes cases:          ", sum(df$diabetes == 1, na.rm = TRUE), "\n")
cat("Hypertension (non-missing):", sum(!is.na(df$hypertension)), "\n")
cat("Hypertension cases:      ", sum(df$hypertension == 1, na.rm = TRUE), "\n")

# -----------------------------------------------------------------------------
# 8. Save Processed Data
# -----------------------------------------------------------------------------

# Create output directory
invisible(results_dir())

# Save as RDS for efficient loading
saveRDS(df, results_path("nhanes_processed.rds"))
saveRDS(design, results_path("survey_design.rds"))

cat("\nData saved to:\n")
cat("  ", results_path("nhanes_processed.rds"), "\n", sep = "")
cat("  ", results_path("survey_design.rds"), "\n", sep = "")
cat("These regenerated outputs are follow-up-ready preprocessing artifacts.\n")
cat("They do not replace the frozen `data/` inputs or `expected/` fixtures used to reproduce the accepted paper.\n")
cat("The accepted-paper package remains aligned to the curated two-feature baseline in `data/`.\n")

cat("\n=== Preprocessing Complete ===\n")
