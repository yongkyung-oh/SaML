# =============================================================================
# 02_experiment2_evaluation.R
# Experiment 2: Unweighted vs Survey-Weighted Model Evaluation
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
source(repo_path("code", "helpers_metrics.R"))

library(tidyverse)
library(pROC)

# Load preprocessed data
df     <- readRDS(data_path("nhanes_processed.rds"))

# Create output directory
invisible(results_dir())

cat("Data loaded: n =", nrow(df), "\n\n")

# -----------------------------------------------------------------------------
# 2. Prepare Modeling Data
# -----------------------------------------------------------------------------

# Complete cases for prediction model
model_df <- df %>%
  filter(
    !is.na(diabetes),
    !is.na(RIDAGEYR),
    !is.na(BMXBMI)
  ) %>%
  select(SEQN, diabetes, RIDAGEYR, BMXBMI, female, WTMEC2YR, SDMVSTRA, SDMVPSU)

cat("Modeling dataset: n =", nrow(model_df), "\n")
cat("Diabetes cases:  ", sum(model_df$diabetes), "\n")
cat("Prevalence:      ", round(mean(model_df$diabetes) * 100, 1), "%\n\n")

# -----------------------------------------------------------------------------
# 3. Fit Logistic Regression Model
# -----------------------------------------------------------------------------

cat("=== Fitting Logistic Regression ===\n")
cat("Model: diabetes ~ age + BMI (minimal paper model)\n\n")

model <- glm(diabetes ~ RIDAGEYR + BMXBMI,
             data = model_df, 
             family = binomial)

# Get predictions
pred <- predict(model, type = "response")

# -----------------------------------------------------------------------------
# 4. Unweighted AUC (Standard)
# -----------------------------------------------------------------------------

cat("=== Unweighted AUC ===\n")

roc_unwt <- roc(model_df$diabetes, pred, quiet = TRUE)
auc_unwt <- as.numeric(auc(roc_unwt))
ci_unwt  <- ci.auc(roc_unwt)  # DeLong method

cat(sprintf("AUC: %.3f (95%% CI: %.3f - %.3f)\n\n", 
            auc_unwt, ci_unwt[1], ci_unwt[3]))

# -----------------------------------------------------------------------------
# 5. Weighted AUC (Horvitz-Thompson Estimator)
# -----------------------------------------------------------------------------

cat("=== Weighted AUC ===\n")

# Calculate weighted AUC
auc_wt <- weighted_auc(model_df$diabetes, pred, model_df$WTMEC2YR)

# Bootstrap CI for weighted AUC
set.seed(42)
n_boot <- 100
boot_auc <- numeric(n_boot)

cat("Running bootstrap (", n_boot, " replications)...\n", sep = "")

for (b in 1:n_boot) {
  idx <- sample(nrow(model_df), replace = TRUE)
  boot_df <- model_df[idx, ]
  boot_auc[b] <- weighted_auc(boot_df$diabetes, pred[idx], boot_df$WTMEC2YR)
  
  if (b %% 25 == 0) cat("  Bootstrap", b, "/", n_boot, "complete\n")
}

ci_wt <- quantile(boot_auc, c(0.025, 0.975), na.rm = TRUE)

cat(sprintf("\nWeighted AUC: %.3f (95%% CI: %.3f - %.3f)\n\n", 
            auc_wt, ci_wt[1], ci_wt[2]))

# -----------------------------------------------------------------------------
# 6. Comparison Summary
# -----------------------------------------------------------------------------

cat("=== Comparison ===\n")
cat(sprintf("Unweighted AUC: %.3f\n", auc_unwt))
cat(sprintf("Weighted AUC:   %.3f\n", auc_wt))
cat(sprintf("Difference:     %.3f\n\n", auc_wt - auc_unwt))

# -----------------------------------------------------------------------------
# 7. Generate LaTeX Table
# -----------------------------------------------------------------------------

cat("% LaTeX Table: AUC Comparison\n")
cat("\\begin{table}[h]\n")
cat("\\centering\n")
cat("\\caption{Comparison of Unweighted and Survey-Weighted AUC for Diabetes Prediction}\n")
cat("\\label{tab:weighted_auc}\n")
cat("\\begin{tabular}{lcc}\n")
cat("\\toprule\n")
cat("Evaluation Method & AUC & 95\\% CI \\\\\n")
cat("\\midrule\n")
cat(sprintf("Unweighted & %.3f & (%.3f -- %.3f) \\\\\n", auc_unwt, ci_unwt[1], ci_unwt[3]))
cat(sprintf("Survey-weighted & %.3f & (%.3f -- %.3f) \\\\\n", auc_wt, ci_wt[1], ci_wt[2]))
cat("\\midrule\n")
cat(sprintf("Difference & %.3f & \\\\\n", auc_wt - auc_unwt))
cat("\\bottomrule\n")
cat("\\end{tabular}\n")
cat("\\end{table}\n\n")

# -----------------------------------------------------------------------------
# 8. Save Results
# -----------------------------------------------------------------------------

exp2_results <- list(
  model      = model,
  auc_unwt   = auc_unwt,
  ci_unwt    = c(ci_unwt[1], ci_unwt[3]),
  auc_wt     = auc_wt,
  ci_wt      = ci_wt,
  difference = auc_wt - auc_unwt,
  n_boot     = n_boot,
  boot_auc   = boot_auc
)

saveRDS(exp2_results, results_path("exp2_evaluation.rds"))
saveRDS(model_df, results_path("model_df.rds"))

cat("=== Experiment 2 Complete ===\n")
cat("Results saved to: ", results_path("exp2_evaluation.rds"), "\n", sep = "")
cat("Model data saved to: ", results_path("model_df.rds"), "\n", sep = "")
