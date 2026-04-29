# =============================================================================
# 01_experiment1_descriptive.R
# Experiment 1: Weighted vs Unweighted Descriptive Statistics
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Setup
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
library(tidyverse)

# Load preprocessed data
df     <- readRDS(data_path("nhanes_processed.rds"))
design <- readRDS(data_path("survey_design.rds"))

cat("Data loaded: n =", nrow(df), "\n\n")

# Create output directory
invisible(results_dir())

# =============================================================================
# Experiment 1a: Continuous Variables
# =============================================================================

cat("=== Experiment 1a: Continuous Variables ===\n\n")

compare_continuous <- function(var_name, design, data, label = var_name) {
  # Filter non-missing
  data_clean <- data %>% filter(!is.na(.data[[var_name]]))
  
  # Unweighted statistics
  unwt_mean <- mean(data_clean[[var_name]], na.rm = TRUE)
  unwt_sd   <- sd(data_clean[[var_name]], na.rm = TRUE)
  unwt_n    <- nrow(data_clean)
  unwt_se   <- unwt_sd / sqrt(unwt_n)
  
  # Weighted statistics (design-based)
  design_clean <- subset(design, !is.na(get(var_name)))
  formula <- as.formula(paste0("~", var_name))
  wt <- svymean(formula, design_clean, na.rm = TRUE)
  wt_mean <- as.numeric(coef(wt))
  wt_se   <- as.numeric(SE(wt))
  
  tibble(
    Variable  = label,
    n         = unwt_n,
    Unwt_Mean = round(unwt_mean, 1),
    Unwt_SE   = round(unwt_se, 2),
    Wt_Mean   = round(wt_mean, 1),
    Wt_SE     = round(wt_se, 2),
    Diff      = round(wt_mean - unwt_mean, 1),
    Pct_Diff  = round((wt_mean - unwt_mean) / unwt_mean * 100, 1)
  )
}

# Calculate for each variable
exp1a_results <- bind_rows(
  compare_continuous("RIDAGEYR", design, df, "Age (years)"),
  compare_continuous("BMXBMI",   design, df, "BMI (kg/m²)"),
  compare_continuous("BPXOSY1",  design, df, "Systolic BP (mmHg)"),
  compare_continuous("BPXODI1",  design, df, "Diastolic BP (mmHg)")
)

print(exp1a_results, width = Inf)

# Generate LaTeX table
cat("\n% LaTeX Table: Continuous Variables\n")
cat("\\begin{table}[h]\n")
cat("\\small\\centering\n")
cat("\\caption{Comparison of Unweighted and Weighted Estimates for Continuous Variables}\n")
cat("\\label{tab:weighted_continuous}\n")
cat("\\begin{tabular}{lcccccc}\n")
cat("\\toprule\n")
cat("\\multirow{2.5}{*}{Variable} & \\multicolumn{2}{c}{Unweighted} & \\multicolumn{2}{c}{Weighted} & \\multirow{2.5}{*}{Diff} & \\multirow{2.5}{*}{\\% Diff} \\\\\n")
cat("\\cmidrule(lr){2-3} \\cmidrule(lr){4-5}\n")
cat(" & Mean & SE & Mean & SE & & \\\\\n")
cat("\\midrule\n")
for (i in 1:nrow(exp1a_results)) {
  cat(sprintf("%s & %.1f & %.2f & %.1f & %.2f & %.1f & %.1f\\%% \\\\\n",
              exp1a_results$Variable[i],
              exp1a_results$Unwt_Mean[i], exp1a_results$Unwt_SE[i],
              exp1a_results$Wt_Mean[i], exp1a_results$Wt_SE[i],
              exp1a_results$Diff[i], exp1a_results$Pct_Diff[i]))
}
cat("\\bottomrule\n")
cat("\\end{tabular}\n")
cat("\\end{table}\n")

# =============================================================================
# Experiment 1b: Disease Prevalence
# =============================================================================

cat("\n\n=== Experiment 1b: Disease Prevalence ===\n\n")

compare_prevalence <- function(var_name, design, data, label = var_name) {
  # Filter non-missing
  data_clean <- data %>% filter(!is.na(.data[[var_name]]))
  
  # Unweighted prevalence
  unwt_prev <- mean(data_clean[[var_name]], na.rm = TRUE)
  unwt_n    <- nrow(data_clean)
  unwt_se   <- sqrt(unwt_prev * (1 - unwt_prev) / unwt_n)
  
  # Weighted prevalence (design-based)
  design_clean <- subset(design, !is.na(get(var_name)))
  formula <- as.formula(paste0("~", var_name))
  wt <- svymean(formula, design_clean, na.rm = TRUE)
  wt_prev <- as.numeric(coef(wt))
  wt_se   <- as.numeric(SE(wt))
  
  tibble(
    Outcome  = label,
    n        = unwt_n,
    Cases    = sum(data_clean[[var_name]] == 1),
    Unwt_Pct = round(unwt_prev * 100, 1),
    Unwt_SE  = round(unwt_se * 100, 2),
    Wt_Pct   = round(wt_prev * 100, 1),
    Wt_SE    = round(wt_se * 100, 2),
    Diff_pp  = round((wt_prev - unwt_prev) * 100, 1)
  )
}

exp1b_results <- bind_rows(
  compare_prevalence("diabetes",     design, df, "Diabetes"),
  compare_prevalence("hypertension", design, df, "Hypertension")
)

print(exp1b_results, width = Inf)

# Generate LaTeX table
cat("\n% LaTeX Table: Prevalence\n")
cat("\\begin{table}[h]\n")
cat("\\centering\n")
cat("\\caption{Comparison of Unweighted and Weighted Prevalence Estimates}\n")
cat("\\label{tab:weighted_prevalence}\n")
cat("\\begin{tabular}{lccccc}\n")
cat("\\toprule\n")
cat("Outcome & $n$ & Unweighted \\% (SE) & Weighted \\% (SE) & Diff (pp) \\\\\n")
cat("\\midrule\n")
for (i in 1:nrow(exp1b_results)) {
  cat(sprintf("%s & %d & %.1f (%.2f) & %.1f (%.2f) & %.1f \\\\\n",
              exp1b_results$Outcome[i], exp1b_results$n[i],
              exp1b_results$Unwt_Pct[i], exp1b_results$Unwt_SE[i],
              exp1b_results$Wt_Pct[i], exp1b_results$Wt_SE[i],
              exp1b_results$Diff_pp[i]))
}
cat("\\bottomrule\n")
cat("\\end{tabular}\n")
cat("\\end{table}\n")

# =============================================================================
# Experiment 1c: Sample Composition by Age Group
# =============================================================================

cat("\n\n=== Experiment 1c: Age Group Composition ===\n\n")

# Unweighted sample proportions
age_unwt <- df %>%
  filter(!is.na(age_group)) %>%
  count(age_group) %>%
  mutate(Unwt_Pct = n / sum(n) * 100)

# Weighted population proportions
age_wt <- svymean(~age_group, design, na.rm = TRUE)

# Combine results
exp1c_age <- age_unwt %>%
  mutate(
    Age_Group = as.character(age_group),
    Unwt_Pct  = round(Unwt_Pct, 1),
    Wt_Pct    = round(as.numeric(coef(age_wt)) * 100, 1),
    Wt_SE     = round(as.numeric(SE(age_wt)) * 100, 2),
    Diff_pp   = round(Wt_Pct - Unwt_Pct, 1)
  ) %>%
  select(Age_Group, n, Unwt_Pct, Wt_Pct, Wt_SE, Diff_pp)

print(exp1c_age)

# Generate LaTeX table
cat("\n% LaTeX Table: Age Group\n")
cat("\\begin{table}[h]\n")
cat("\\centering\n")
cat("\\caption{Sample Composition vs Population Estimates by Age Group}\n")
cat("\\label{tab:age_representation}\n")
cat("\\begin{tabular}{lcccc}\n")
cat("\\toprule\n")
cat("Age Group & $n$ & Sample \\% & Population \\% (SE) & Diff (pp) \\\\\n")
cat("\\midrule\n")
for (i in 1:nrow(exp1c_age)) {
  sign <- ifelse(exp1c_age$Diff_pp[i] >= 0, "+", "")
  cat(sprintf("%s & %d & %.1f & %.1f (%.2f) & %s%.1f \\\\\n",
              exp1c_age$Age_Group[i], exp1c_age$n[i],
              exp1c_age$Unwt_Pct[i], exp1c_age$Wt_Pct[i], exp1c_age$Wt_SE[i],
              sign, exp1c_age$Diff_pp[i]))
}
cat("\\bottomrule\n")
cat("\\end{tabular}\n")
cat("\\end{table}\n")

# =============================================================================
# Experiment 1c (cont.): Sample Composition by Race/Ethnicity
# =============================================================================

cat("\n\n=== Experiment 1c: Race/Ethnicity Composition ===\n\n")

# Unweighted sample proportions
race_unwt <- df %>%
  filter(!is.na(RIDRETH3)) %>%
  count(RIDRETH3) %>%
  mutate(Unwt_Pct = n / sum(n) * 100)

# Weighted population proportions
race_wt <- svymean(~RIDRETH3, design, na.rm = TRUE)

# Combine results
exp1c_race <- race_unwt %>%
  mutate(
    Race     = as.character(RIDRETH3),
    Unwt_Pct = round(Unwt_Pct, 1),
    Wt_Pct   = round(as.numeric(coef(race_wt)) * 100, 1),
    Wt_SE    = round(as.numeric(SE(race_wt)) * 100, 2),
    Diff_pp  = round(Wt_Pct - Unwt_Pct, 1)
  ) %>%
  select(Race, n, Unwt_Pct, Wt_Pct, Wt_SE, Diff_pp)

print(exp1c_race)

# =============================================================================
# Save Results
# =============================================================================

saveRDS(list(
  continuous = exp1a_results,
  prevalence = exp1b_results,
  age_group  = exp1c_age,
  race_eth   = exp1c_race
), results_path("exp1_descriptive.rds"))

cat("\n\n=== Experiment 1 Complete ===\n")
cat("Results saved to: ", results_path("exp1_descriptive.rds"), "\n", sep = "")
