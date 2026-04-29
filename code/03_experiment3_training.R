# =============================================================================
# 03_experiment3_training.R
# Experiment 3: Effect of Survey Weights in XGBoost Training
# 2x2 Factorial Design: Training Method × Evaluation Method
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

library(survey)
library(tidyverse)
library(xgboost)
library(pROC)

# Load preprocessed data
model_df <- readRDS(data_path("model_df.rds"))

# Create output directory
invisible(results_dir())

cat("Data loaded: n =", nrow(model_df), "\n")
cat("Diabetes prevalence:", round(mean(model_df$diabetes) * 100, 1), "%\n\n")

# -----------------------------------------------------------------------------
# 2. Prepare XGBoost Data
# -----------------------------------------------------------------------------

# Accepted-paper minimal model: age + BMI only.
X <- as.matrix(model_df[, c("RIDAGEYR", "BMXBMI")])
colnames(X) <- c("age", "bmi")

# Outcome and weights
y       <- model_df$diabetes
weights <- model_df$WTMEC2YR

cat("Features:", paste(colnames(X), collapse = ", "), "\n")
cat("Sample size:", length(y), "\n\n")

# -----------------------------------------------------------------------------
# 3. Define Helper Functions
# -----------------------------------------------------------------------------

#' Standard (unweighted) Precision-Recall curve
standard_pr <- function(y, pred, n_thresholds = 200) {
  thresholds <- seq(0.01, 0.99, length.out = n_thresholds)
  
  results <- map_df(thresholds, function(t) {
    pred_class <- as.numeric(pred >= t)
    
    tp <- sum(y == 1 & pred_class == 1)
    fp <- sum(y == 0 & pred_class == 1)
    fn <- sum(y == 1 & pred_class == 0)
    
    precision <- ifelse((tp + fp) > 0, tp / (tp + fp), NA)
    recall    <- tp / (tp + fn)
    
    tibble(threshold = t, Precision = precision, Recall = recall)
  }) %>%
    filter(!is.na(Precision))
  
  return(results)
}

#' Weighted Precision-Recall curve
weighted_pr <- function(y, pred, weights, n_thresholds = 200) {
  thresholds <- seq(0.01, 0.99, length.out = n_thresholds)
  
  results <- map_df(thresholds, function(t) {
    pred_class <- as.numeric(pred >= t)
    
    w_tp <- sum(weights[y == 1 & pred_class == 1])
    w_fp <- sum(weights[y == 0 & pred_class == 1])
    w_precision <- ifelse((w_tp + w_fp) > 0, w_tp / (w_tp + w_fp), NA)
    
    w_fn <- sum(weights[y == 1 & pred_class == 0])
    w_recall <- w_tp / (w_tp + w_fn)
    
    tibble(threshold = t, Precision = w_precision, Recall = w_recall)
  }) %>%
    filter(!is.na(Precision))
  
  return(results)
}

#' Calculate AUPRC using trapezoidal rule
calc_auprc <- function(pr_data) {
  pr_sorted <- pr_data %>% arrange(Recall)
  auprc <- sum(diff(pr_sorted$Recall) * 
               (head(pr_sorted$Precision, -1) + tail(pr_sorted$Precision, -1)) / 2)
  return(auprc)
}

# -----------------------------------------------------------------------------
# 4. Train XGBoost Models
# -----------------------------------------------------------------------------

cat("=== Training XGBoost Models ===\n\n")

# XGBoost hyperparameters
params <- list(
  objective        = "binary:logistic",
  eval_metric      = "auc",
  max_depth        = 3,
  eta              = 0.1,
  subsample        = 1,
  colsample_bytree = 1
)
nrounds <- 100

# Set seed before any stochastic operations (XGBoost uses internal RNG)
set.seed(42)

# Unweighted training
cat("Training unweighted XGBoost...\n")
dtrain_unwt <- xgb.DMatrix(data = X, label = y)
xgb_unwt    <- xgb.train(params = params, data = dtrain_unwt, nrounds = nrounds, verbose = 0)
pred_unwt   <- predict(xgb_unwt, X)

# Weighted training
cat("Training weighted XGBoost...\n")
dtrain_wt <- xgb.DMatrix(data = X, label = y, weight = weights)
xgb_wt    <- xgb.train(params = params, data = dtrain_wt, nrounds = nrounds, verbose = 0)
pred_wt   <- predict(xgb_wt, X)

cat("Training complete.\n\n")

# -----------------------------------------------------------------------------
# 5. Calculate Point Estimates (2x2 Factorial)
# -----------------------------------------------------------------------------

cat("=== Calculating Point Estimates ===\n\n")

# AUC
auc_unwt_model_unwt_eval <- as.numeric(auc(roc(y, pred_unwt, quiet = TRUE)))
auc_wt_model_unwt_eval   <- as.numeric(auc(roc(y, pred_wt, quiet = TRUE)))
auc_unwt_model_wt_eval   <- weighted_auc(y, pred_unwt, weights)
auc_wt_model_wt_eval     <- weighted_auc(y, pred_wt, weights)

# PR curves
pr_unwt_std <- standard_pr(y, pred_unwt)
pr_wt_std   <- standard_pr(y, pred_wt)
pr_unwt_wt  <- weighted_pr(y, pred_unwt, weights)
pr_wt_wt    <- weighted_pr(y, pred_wt, weights)

# AUPRC
auprc_unwt_model_unwt_eval <- calc_auprc(pr_unwt_std)
auprc_wt_model_unwt_eval   <- calc_auprc(pr_wt_std)
auprc_unwt_model_wt_eval   <- calc_auprc(pr_unwt_wt)
auprc_wt_model_wt_eval     <- calc_auprc(pr_wt_wt)

# -----------------------------------------------------------------------------
# 6. Bootstrap Confidence Intervals
# -----------------------------------------------------------------------------

cat("=== Bootstrap Confidence Intervals ===\n")

set.seed(42)
n_boot <- 100

boot_auc   <- matrix(NA, nrow = n_boot, ncol = 4)
boot_auprc <- matrix(NA, nrow = n_boot, ncol = 4)
colnames(boot_auc) <- colnames(boot_auprc) <- c("unwt_unwt", "wt_unwt", "unwt_wt", "wt_wt")

cat("Running bootstrap (", n_boot, " replications)...\n", sep = "")

for (b in 1:n_boot) {
  idx <- sample(length(y), replace = TRUE)
  y_b       <- y[idx]
  pred_unwt_b <- pred_unwt[idx]
  pred_wt_b   <- pred_wt[idx]
  w_b       <- weights[idx]
  
  # AUC - Unweighted evaluation
  boot_auc[b, "unwt_unwt"] <- as.numeric(auc(roc(y_b, pred_unwt_b, quiet = TRUE)))
  boot_auc[b, "wt_unwt"]   <- as.numeric(auc(roc(y_b, pred_wt_b, quiet = TRUE)))
  
  # AUC - Weighted evaluation
  boot_auc[b, "unwt_wt"] <- weighted_auc(y_b, pred_unwt_b, w_b)
  boot_auc[b, "wt_wt"]   <- weighted_auc(y_b, pred_wt_b, w_b)
  
  # AUPRC - Standard
  pr_unwt_b <- standard_pr(y_b, pred_unwt_b)
  pr_wt_b   <- standard_pr(y_b, pred_wt_b)
  boot_auprc[b, "unwt_unwt"] <- calc_auprc(pr_unwt_b)
  boot_auprc[b, "wt_unwt"]   <- calc_auprc(pr_wt_b)
  
  # AUPRC - Weighted
  pr_unwt_wt_b <- weighted_pr(y_b, pred_unwt_b, w_b)
  pr_wt_wt_b   <- weighted_pr(y_b, pred_wt_b, w_b)
  boot_auprc[b, "unwt_wt"] <- calc_auprc(pr_unwt_wt_b)
  boot_auprc[b, "wt_wt"]   <- calc_auprc(pr_wt_wt_b)
  
  if (b %% 20 == 0) cat("  Bootstrap", b, "/", n_boot, "complete\n")
}

# 95% CI - AUC
ci_auc_unwt_unwt <- quantile(boot_auc[, "unwt_unwt"], c(0.025, 0.975), na.rm = TRUE)
ci_auc_wt_unwt   <- quantile(boot_auc[, "wt_unwt"],   c(0.025, 0.975), na.rm = TRUE)
ci_auc_unwt_wt   <- quantile(boot_auc[, "unwt_wt"],   c(0.025, 0.975), na.rm = TRUE)
ci_auc_wt_wt     <- quantile(boot_auc[, "wt_wt"],     c(0.025, 0.975), na.rm = TRUE)

# 95% CI - AUPRC
ci_auprc_unwt_unwt <- quantile(boot_auprc[, "unwt_unwt"], c(0.025, 0.975), na.rm = TRUE)
ci_auprc_wt_unwt   <- quantile(boot_auprc[, "wt_unwt"],   c(0.025, 0.975), na.rm = TRUE)
ci_auprc_unwt_wt   <- quantile(boot_auprc[, "unwt_wt"],   c(0.025, 0.975), na.rm = TRUE)
ci_auprc_wt_wt     <- quantile(boot_auprc[, "wt_wt"],     c(0.025, 0.975), na.rm = TRUE)

# -----------------------------------------------------------------------------
# 7. Results Summary
# -----------------------------------------------------------------------------

cat("\n=== Results Summary ===\n\n")

cat("AUC (2x2 Factorial: Training × Evaluation):\n")
cat("---------------------------------------------------------------\n")
cat(sprintf("                    | Unwt Eval           | Wt Eval\n"))
cat("---------------------------------------------------------------\n")
cat(sprintf("Unwt Training       | %.3f (%.3f--%.3f) | %.3f (%.3f--%.3f)\n",
            auc_unwt_model_unwt_eval, ci_auc_unwt_unwt[1], ci_auc_unwt_unwt[2],
            auc_unwt_model_wt_eval, ci_auc_unwt_wt[1], ci_auc_unwt_wt[2]))
cat(sprintf("Wt Training         | %.3f (%.3f--%.3f) | %.3f (%.3f--%.3f)\n",
            auc_wt_model_unwt_eval, ci_auc_wt_unwt[1], ci_auc_wt_unwt[2],
            auc_wt_model_wt_eval, ci_auc_wt_wt[1], ci_auc_wt_wt[2]))
cat("---------------------------------------------------------------\n")
cat(sprintf("Difference          | %.3f               | %.3f\n\n",
            auc_wt_model_unwt_eval - auc_unwt_model_unwt_eval,
            auc_wt_model_wt_eval - auc_unwt_model_wt_eval))

cat("AUPRC (2x2 Factorial: Training × Evaluation):\n")
cat("---------------------------------------------------------------\n")
cat(sprintf("                    | Unwt Eval           | Wt Eval\n"))
cat("---------------------------------------------------------------\n")
cat(sprintf("Unwt Training       | %.3f (%.3f--%.3f) | %.3f (%.3f--%.3f)\n",
            auprc_unwt_model_unwt_eval, ci_auprc_unwt_unwt[1], ci_auprc_unwt_unwt[2],
            auprc_unwt_model_wt_eval, ci_auprc_unwt_wt[1], ci_auprc_unwt_wt[2]))
cat(sprintf("Wt Training         | %.3f (%.3f--%.3f) | %.3f (%.3f--%.3f)\n",
            auprc_wt_model_unwt_eval, ci_auprc_wt_unwt[1], ci_auprc_wt_unwt[2],
            auprc_wt_model_wt_eval, ci_auprc_wt_wt[1], ci_auprc_wt_wt[2]))
cat("---------------------------------------------------------------\n")
cat(sprintf("Difference          | %.3f               | %.3f\n\n",
            auprc_wt_model_unwt_eval - auprc_unwt_model_unwt_eval,
            auprc_wt_model_wt_eval - auprc_unwt_model_wt_eval))

# -----------------------------------------------------------------------------
# 8. Generate LaTeX Table
# -----------------------------------------------------------------------------

cat("% LaTeX Table: XGBoost Results - AUC and AUPRC\n")
cat("\\begin{table}[h]\n")
cat("\\small\\centering\n")
cat("\\caption{Effect of Survey Weights in XGBoost Training: AUC and AUPRC}\n")
cat("\\label{tab:xgboost_auc_auprc}\n")
cat("\\begin{tabular}{lcccc}\n")
cat("\\toprule\n")
cat(" & \\multicolumn{2}{c}{AUC} & \\multicolumn{2}{c}{AUPRC} \\\\\n")
cat("\\cmidrule(lr){2-3} \\cmidrule(lr){4-5}\n")
cat("Training Method & Unweighted & Weighted & Unweighted & Weighted \\\\\n")
cat("\\midrule\n")
cat(sprintf("Unweighted XGBoost & %.3f (%.3f--%.3f) & %.3f (%.3f--%.3f) & %.3f (%.3f--%.3f) & %.3f (%.3f--%.3f) \\\\\n",
            auc_unwt_model_unwt_eval, ci_auc_unwt_unwt[1], ci_auc_unwt_unwt[2],
            auc_unwt_model_wt_eval, ci_auc_unwt_wt[1], ci_auc_unwt_wt[2],
            auprc_unwt_model_unwt_eval, ci_auprc_unwt_unwt[1], ci_auprc_unwt_unwt[2],
            auprc_unwt_model_wt_eval, ci_auprc_unwt_wt[1], ci_auprc_unwt_wt[2]))
cat(sprintf("Weighted XGBoost & %.3f (%.3f--%.3f) & %.3f (%.3f--%.3f) & %.3f (%.3f--%.3f) & %.3f (%.3f--%.3f) \\\\\n",
            auc_wt_model_unwt_eval, ci_auc_wt_unwt[1], ci_auc_wt_unwt[2],
            auc_wt_model_wt_eval, ci_auc_wt_wt[1], ci_auc_wt_wt[2],
            auprc_wt_model_unwt_eval, ci_auprc_wt_unwt[1], ci_auprc_wt_unwt[2],
            auprc_wt_model_wt_eval, ci_auprc_wt_wt[1], ci_auprc_wt_wt[2]))
cat("\\midrule\n")
cat(sprintf("Difference & %.3f & %.3f & %.3f & %.3f \\\\\n",
            auc_wt_model_unwt_eval - auc_unwt_model_unwt_eval,
            auc_wt_model_wt_eval - auc_unwt_model_wt_eval,
            auprc_wt_model_unwt_eval - auprc_unwt_model_unwt_eval,
            auprc_wt_model_wt_eval - auprc_unwt_model_wt_eval))
cat("\\bottomrule\n")
cat("\\end{tabular}\n")
cat("\\begin{tablenotes}\n")
cat("\\small\n")
cat(sprintf("\\item \\textit{Note}: Values reported as metric (95\\%% bootstrap CI, %d replications).\n", n_boot))
cat("\\item AUPRC = Area Under Precision-Recall Curve.\n")
cat("\\end{tablenotes}\n")
cat("\\end{table}\n\n")

# -----------------------------------------------------------------------------
# 9. Save Results
# -----------------------------------------------------------------------------

exp3_results <- list(
  # Point estimates
  auc = list(
    unwt_unwt = auc_unwt_model_unwt_eval,
    wt_unwt   = auc_wt_model_unwt_eval,
    unwt_wt   = auc_unwt_model_wt_eval,
    wt_wt     = auc_wt_model_wt_eval
  ),
  auprc = list(
    unwt_unwt = auprc_unwt_model_unwt_eval,
    wt_unwt   = auprc_wt_model_unwt_eval,
    unwt_wt   = auprc_unwt_model_wt_eval,
    wt_wt     = auprc_wt_model_wt_eval
  ),
  # Confidence intervals
  ci_auc = list(
    unwt_unwt = ci_auc_unwt_unwt,
    wt_unwt   = ci_auc_wt_unwt,
    unwt_wt   = ci_auc_unwt_wt,
    wt_wt     = ci_auc_wt_wt
  ),
  ci_auprc = list(
    unwt_unwt = ci_auprc_unwt_unwt,
    wt_unwt   = ci_auprc_wt_unwt,
    unwt_wt   = ci_auprc_unwt_wt,
    wt_wt     = ci_auprc_wt_wt
  ),
  # Bootstrap samples
  boot_auc   = boot_auc,
  boot_auprc = boot_auprc,
  n_boot     = n_boot,
  # Models
  xgb_unwt   = xgb_unwt,
  xgb_wt     = xgb_wt,
  # Predictions
  pred_unwt  = pred_unwt,
  pred_wt    = pred_wt
)

saveRDS(exp3_results, results_path("exp3_training.rds"))

cat("=== Experiment 3 Complete ===\n")
cat("Results saved to: ", results_path("exp3_training.rds"), "\n", sep = "")
