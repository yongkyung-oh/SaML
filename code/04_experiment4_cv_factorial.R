# =============================================================================
# 04_experiment4_cv_factorial.R
# Experiment 4: Full Factorial Cross-Validation
# 2 (CV Type) × 2 (Training) × 2 (Evaluation) = 8 conditions
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
library(xgboost)
library(pROC)
library(tidyverse)

# Load preprocessed data
model_df <- readRDS(data_path("model_df.rds"))

# Create output directory
invisible(results_dir())

cat("Data loaded: n =", nrow(model_df), "\n\n")

# -----------------------------------------------------------------------------
# 2. Prepare Data
# -----------------------------------------------------------------------------

# Accepted-paper minimal model: age + BMI only.
X <- as.matrix(model_df[, c("RIDAGEYR", "BMXBMI")])
colnames(X) <- c("age", "bmi")

# Outcome and weights
y       <- model_df$diabetes
weights <- model_df$WTMEC2YR

# PSU mapping for cluster-based CV
model_df <- model_df %>%
  mutate(psu_id = paste(SDMVSTRA, SDMVPSU, sep = "_"))

unique_psus <- unique(model_df$psu_id)
n_psus <- length(unique_psus)

# -----------------------------------------------------------------------------
# 3. Experiment Parameters
# -----------------------------------------------------------------------------

set.seed(42)

n_folds   <- 5
n_repeats <- 3

params <- list(
  objective   = "binary:logistic",
  eval_metric = "auc",
  max_depth   = 3,
  eta         = 0.1
)
nrounds <- 100

cat("=== Experiment Setup ===\n")
cat("Samples:     ", nrow(model_df), "\n")
cat("Unique PSUs: ", n_psus, "\n")
cat("Folds:       ", n_folds, " × Repeats: ", n_repeats, " = ", 
    n_folds * n_repeats, " iterations per CV type\n", sep = "")
cat("Conditions:   2 (CV) × 2 (Train) × 2 (Eval) = 8\n\n")

# -----------------------------------------------------------------------------
# 4. Helper Functions
# -----------------------------------------------------------------------------

#' Standard (unweighted) Precision-Recall curve
standard_pr <- function(y, pred, n_thresholds = 100) {
  thresholds <- seq(0.01, 0.99, length.out = n_thresholds)
  map_df(thresholds, function(t) {
    pred_class <- as.numeric(pred >= t)
    tp <- sum(y == 1 & pred_class == 1)
    fp <- sum(y == 0 & pred_class == 1)
    fn <- sum(y == 1 & pred_class == 0)
    precision <- ifelse((tp + fp) > 0, tp / (tp + fp), NA)
    recall <- tp / (tp + fn)
    tibble(Precision = precision, Recall = recall)
  }) %>% filter(!is.na(Precision))
}

#' Weighted Precision-Recall curve
weighted_pr <- function(y, pred, weights, n_thresholds = 100) {
  thresholds <- seq(0.01, 0.99, length.out = n_thresholds)
  map_df(thresholds, function(t) {
    pred_class <- as.numeric(pred >= t)
    w_tp <- sum(weights[y == 1 & pred_class == 1])
    w_fp <- sum(weights[y == 0 & pred_class == 1])
    w_fn <- sum(weights[y == 1 & pred_class == 0])
    precision <- ifelse((w_tp + w_fp) > 0, w_tp / (w_tp + w_fp), NA)
    recall <- w_tp / (w_tp + w_fn)
    tibble(Precision = precision, Recall = recall)
  }) %>% filter(!is.na(Precision))
}

#' Calculate AUPRC using trapezoidal rule
calc_auprc <- function(pr_data) {
  pr_sorted <- pr_data %>% arrange(Recall)
  sum(diff(pr_sorted$Recall) * 
      (head(pr_sorted$Precision, -1) + tail(pr_sorted$Precision, -1)) / 2)
}

# -----------------------------------------------------------------------------
# 5. Main Experiment Loop
# -----------------------------------------------------------------------------

cat("=== Running Full Factorial Experiment ===\n\n")

results <- tibble()

for (cv_type in c("Random", "PSU")) {
  
  for (r in 1:n_repeats) {
    
    # Create fold assignments
    if (cv_type == "Random") {
      # Standard random fold assignment
      fold_idx <- sample(rep(1:n_folds, length.out = nrow(model_df)))
    } else {
      # Stratified PSU-level assignment (survey-aware)
      # Assign folds separately within each stratum to ensure balance
      psu_info <- model_df %>% distinct(psu_id, SDMVSTRA)
      psu_info$fold <- NA_integer_
      for (s in unique(psu_info$SDMVSTRA)) {
        idx <- which(psu_info$SDMVSTRA == s)
        psu_info$fold[idx] <- sample(rep(1:n_folds, length.out = length(idx)))
      }
      psu_fold_map <- setNames(psu_info$fold, psu_info$psu_id)
      fold_idx <- psu_fold_map[model_df$psu_id]
    }
    
    for (f in 1:n_folds) {
      
      # Split data
      test_idx  <- which(fold_idx == f)
      train_idx <- which(fold_idx != f)
      
      # Skip if insufficient samples
      if (length(test_idx) < 30 || sum(y[test_idx]) < 5) {
        cat("Skipping:", cv_type, "R", r, "F", f, "- insufficient samples\n")
        next
      }
      
      X_train <- X[train_idx, ]
      X_test  <- X[test_idx, ]
      y_train <- y[train_idx]
      y_test  <- y[test_idx]
      w_train <- weights[train_idx]
      w_test  <- weights[test_idx]
      
      # ----------------------------------------
      # Train: Unweighted vs Weighted
      # ----------------------------------------
      
      for (train_type in c("Unweighted", "Weighted")) {
        
        if (train_type == "Unweighted") {
          dtrain <- xgb.DMatrix(data = X_train, label = y_train)
        } else {
          dtrain <- xgb.DMatrix(data = X_train, label = y_train, weight = w_train)
        }
        
        model <- xgb.train(params = params, data = dtrain, nrounds = nrounds, verbose = 0)
        pred  <- predict(model, X_test)
        
        # ----------------------------------------
        # Evaluate: Unweighted vs Weighted
        # ----------------------------------------
        
        for (eval_type in c("Unweighted", "Weighted")) {
          
          # AUC
          if (eval_type == "Unweighted") {
            auc_val <- as.numeric(auc(roc(y_test, pred, quiet = TRUE)))
            pr_data <- standard_pr(y_test, pred)
          } else {
            auc_val <- weighted_auc(y_test, pred, w_test)
            pr_data <- weighted_pr(y_test, pred, w_test)
          }
          
          # AUPRC
          auprc_val <- calc_auprc(pr_data)
          
          # Store result
          results <- bind_rows(results, tibble(
            cv_type    = cv_type,
            train_type = train_type,
            eval_type  = eval_type,
            repeat_id  = r,
            fold_id    = f,
            n_test     = length(test_idx),
            n_pos      = sum(y_test),
            auc        = auc_val,
            auprc      = auprc_val
          ))
        }
      }
    }
    
    cat(cv_type, "CV - Repeat", r, "done\n")
  }
}

cat("\n=== Experiment Complete ===\n")
cat("Total results:", nrow(results), "\n\n")

# -----------------------------------------------------------------------------
# 6. Summary Statistics by Condition
# -----------------------------------------------------------------------------

summary_stats <- results %>%
  group_by(cv_type, train_type, eval_type) %>%
  summarise(
    n          = n(),
    auc_mean   = mean(auc),
    auc_sd     = sd(auc),
    auprc_mean = mean(auprc),
    auprc_sd   = sd(auprc),
    .groups    = "drop"
  ) %>%
  arrange(cv_type, train_type, eval_type)

# -----------------------------------------------------------------------------
# 7. Print Formatted Summary
# -----------------------------------------------------------------------------

cat("\n=== Full Factorial Results: AUC ===\n\n")

for (cv in c("Random", "PSU")) {
  cat(sprintf("--- %s CV ---\n", cv))
  cat(sprintf("%-12s  %-12s  %s\n", "Training", "Evaluation", "AUC (mean ± sd)"))
  cat(strrep("-", 50), "\n")
  
  sub <- summary_stats %>% filter(cv_type == cv)
  for (i in 1:nrow(sub)) {
    cat(sprintf("%-12s  %-12s  %.3f ± %.3f\n",
                sub$train_type[i], sub$eval_type[i],
                sub$auc_mean[i], sub$auc_sd[i]))
  }
  cat("\n")
}

cat("\n=== Full Factorial Results: AUPRC ===\n\n")

for (cv in c("Random", "PSU")) {
  cat(sprintf("--- %s CV ---\n", cv))
  cat(sprintf("%-12s  %-12s  %s\n", "Training", "Evaluation", "AUPRC (mean ± sd)"))
  cat(strrep("-", 50), "\n")
  
  sub <- summary_stats %>% filter(cv_type == cv)
  for (i in 1:nrow(sub)) {
    cat(sprintf("%-12s  %-12s  %.3f ± %.3f\n",
                sub$train_type[i], sub$eval_type[i],
                sub$auprc_mean[i], sub$auprc_sd[i]))
  }
  cat("\n")
}

# -----------------------------------------------------------------------------
# 8. Generate LaTeX Table
# -----------------------------------------------------------------------------

cat("\n% LaTeX Table: Full Factorial CV Results\n")
cat("\\begin{table}[h]\n")
cat("\\small\\centering\n")
cat("\\caption{Cross-Validation Results: CV Type $\\times$ Training $\\times$ Evaluation}\n")
cat("\\label{tab:cv_factorial}\n")
cat("\\begin{tabular}{llcccc}\n")
cat("\\toprule\n")
cat(" & & \\multicolumn{2}{c}{AUC} & \\multicolumn{2}{c}{AUPRC} \\\\\n")
cat("\\cmidrule(lr){3-4} \\cmidrule(lr){5-6}\n")
cat("CV Type & Training & Unwt Eval & Wt Eval & Unwt Eval & Wt Eval \\\\\n")
cat("\\midrule\n")

for (cv in c("Random", "PSU")) {
  first_row <- TRUE
  for (train in c("Unweighted", "Weighted")) {
    sub <- summary_stats %>% 
      filter(cv_type == cv, train_type == train)
    
    unwt_eval <- sub %>% filter(eval_type == "Unweighted")
    wt_eval   <- sub %>% filter(eval_type == "Weighted")
    
    cv_label <- ifelse(first_row, cv, "")
    
    cat(sprintf("%s & %s & %.3f (%.3f) & %.3f (%.3f) & %.3f (%.3f) & %.3f (%.3f) \\\\\n",
                cv_label, train,
                unwt_eval$auc_mean, unwt_eval$auc_sd,
                wt_eval$auc_mean, wt_eval$auc_sd,
                unwt_eval$auprc_mean, unwt_eval$auprc_sd,
                wt_eval$auprc_mean, wt_eval$auprc_sd))
    
    first_row <- FALSE
  }
  if (cv == "Random") cat("\\midrule\n")
}

cat("\\bottomrule\n")
cat("\\end{tabular}\n")
cat("\\begin{tablenotes}\n")
cat("\\small\n")
cat(sprintf("\\item \\textit{Note}: Values reported as mean (SD) across %d-fold CV $\\times$ %d repeats.\n", 
            n_folds, n_repeats))
cat("\\item Random = standard random fold assignment; PSU = primary sampling unit-level assignment.\n")
cat("\\end{tablenotes}\n")
cat("\\end{table}\n")

# -----------------------------------------------------------------------------
# 9. Save Results
# -----------------------------------------------------------------------------

exp4_results <- list(
  results       = results,
  summary_stats = summary_stats,
  params        = list(
    n_folds   = n_folds,
    n_repeats = n_repeats,
    xgb_params = params,
    nrounds   = nrounds
  )
)

saveRDS(exp4_results, results_path("exp4_cv_factorial.rds"))

cat("\n=== Experiment 4 Complete ===\n")
cat("Results saved to: ", results_path("exp4_cv_factorial.rds"), "\n", sep = "")
