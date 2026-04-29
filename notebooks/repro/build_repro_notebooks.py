import json
from pathlib import Path
from textwrap import dedent


ROOT = Path(__file__).resolve().parent
CELL_COUNTER = 0


def next_cell_id(prefix: str) -> str:
    global CELL_COUNTER
    CELL_COUNTER += 1
    return f"{prefix}-{CELL_COUNTER:03d}"


def md_cell(text: str) -> dict:
    return {
        "cell_type": "markdown",
        "id": next_cell_id("md"),
        "metadata": {},
        "source": dedent(text).strip("\n").splitlines(keepends=True),
    }


def code_cell(text: str) -> dict:
    return {
        "cell_type": "code",
        "id": next_cell_id("code"),
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": dedent(text).strip("\n").splitlines(keepends=True),
    }


def write_notebook(name: str, cells) -> None:
    payload = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "R", "language": "R", "name": "ir"},
            "language_info": {"name": "R"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    (ROOT / name).write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n")


write_notebook(
    "01_exp1_repro.ipynb",
    [
        md_cell(
            """
            # Exp 1 Reproducibility Check

            This notebook reruns `code/01_experiment1_descriptive.R` in an isolated scratch workspace
            and compares the rerun outputs against `expected/exp1_descriptive.rds`. Figure checks are
            based on figures regenerated from the expected baseline result, not on external `out/` artifacts.
            """
        ),
        code_cell(
            """
            suppressPackageStartupMessages({
              library(survey)
              library(tidyverse)
              library(patchwork)
            })

            helper_candidates <- c("repro_utils.R", file.path("notebooks", "repro", "repro_utils.R"))
            helper_path <- helper_candidates[file.exists(helper_candidates)][1]
            if (is.na(helper_path)) {
              stop("repro_utils.R not found.")
            }
            source(helper_path)

            baseline_result_path <- path_in_repo("expected", "exp1_descriptive.rds")
            scratch_dir <- new_scratch("exp1_repro")

            cat("Scratch workspace:", scratch_dir, "\\n")
            cat("Baseline result:", baseline_result_path, "\\n")
            """
        ),
        code_cell(
            """
            run_script_in_scratch(
              "code/01_experiment1_descriptive.R",
              scratch_dir,
              c("data/nhanes_processed.rds", "data/survey_design.rds")
            )

            baseline_exp1 <- readRDS(baseline_result_path)
            rerun_exp1 <- readRDS(file.path(scratch_dir, "results", "exp1_descriptive.rds"))
            """
        ),
        code_cell(
            """
            numeric_checks <- list(
              compare_df_exact("exp1_continuous", rerun_exp1$continuous, baseline_exp1$continuous),
              compare_df_exact("exp1_prevalence", rerun_exp1$prevalence, baseline_exp1$prevalence),
              compare_df_exact("exp1_age_group", rerun_exp1$age_group, baseline_exp1$age_group),
              compare_df_exact("exp1_race_eth", rerun_exp1$race_eth, baseline_exp1$race_eth)
            )

            bind_rows(numeric_checks)
            """
        ),
        code_cell(
            """
            render_exp1_figures <- function(exp1_obj, out_dir) {
              ensure_dir(out_dir)

              plot_data <- exp1_obj$continuous %>%
                select(Variable, Unweighted = Unwt_Mean, Weighted = Wt_Mean) %>%
                pivot_longer(-Variable, names_to = "Type", values_to = "Mean")

              se_data <- exp1_obj$continuous %>%
                select(Variable, Unweighted = Unwt_SE, Weighted = Wt_SE) %>%
                pivot_longer(-Variable, names_to = "Type", values_to = "SE")

              plot_data <- plot_data %>% left_join(se_data, by = c("Variable", "Type"))
              plot_data$Type <- factor(plot_data$Type, levels = c("Unweighted", "Weighted"))

              p1 <- ggplot(plot_data, aes(x = Variable, y = Mean, fill = Type)) +
                geom_col(position = position_dodge(0.8), width = 0.7) +
                geom_errorbar(aes(ymin = Mean - 1.96 * SE, ymax = Mean + 1.96 * SE),
                              position = position_dodge(0.8), width = 0.2) +
                facet_wrap(~Variable, scales = "free_y", nrow = 1) +
                scale_fill_manual(values = c("Unweighted" = "#4DBBD5", "Weighted" = "#E64B35")) +
                labs(y = "Mean", x = NULL, fill = NULL,
                     title = "Weighted vs Unweighted Means for Continuous Variables") +
                theme_minimal(base_size = 12) +
                theme(legend.position = "bottom",
                      strip.text = element_text(face = "bold"),
                      axis.text.x = element_blank(),
                      axis.ticks.x = element_blank())

              prev_plot <- exp1_obj$prevalence %>%
                select(Outcome, Unweighted = Unwt_Pct, Weighted = Wt_Pct) %>%
                pivot_longer(-Outcome, names_to = "Type", values_to = "Prevalence")

              prev_se <- exp1_obj$prevalence %>%
                select(Outcome, Unweighted = Unwt_SE, Weighted = Wt_SE) %>%
                pivot_longer(-Outcome, names_to = "Type", values_to = "SE")

              prev_plot <- prev_plot %>% left_join(prev_se, by = c("Outcome", "Type"))
              prev_plot$Type <- factor(prev_plot$Type, levels = c("Unweighted", "Weighted"))

              p2 <- ggplot(prev_plot, aes(x = Outcome, y = Prevalence, fill = Type)) +
                geom_col(position = position_dodge(0.8), width = 0.6) +
                geom_errorbar(aes(ymin = Prevalence - 1.96 * SE, ymax = Prevalence + 1.96 * SE),
                              position = position_dodge(0.8), width = 0.2) +
                scale_fill_manual(values = c("Unweighted" = "#4DBBD5", "Weighted" = "#E64B35")) +
                labs(y = "Prevalence (%)", x = NULL, fill = NULL,
                     title = "Weighted vs Unweighted Disease Prevalence") +
                theme_minimal(base_size = 12) +
                theme(legend.position = "bottom")

              age_plot <- exp1_obj$age_group %>%
                select(Group = Age_Group, Sample = Unwt_Pct, Population = Wt_Pct) %>%
                pivot_longer(-Group, names_to = "Type", values_to = "Pct")
              age_plot$Type <- factor(age_plot$Type, levels = c("Sample", "Population"))

              p3a <- ggplot(age_plot, aes(x = Group, y = Pct, fill = Type)) +
                geom_col(position = position_dodge(0.8), width = 0.6) +
                scale_fill_manual(values = c("Sample" = "#4DBBD5", "Population" = "#E64B35")) +
                labs(y = "Proportion (%)", x = NULL, fill = NULL,
                     title = "Age Group Composition") +
                theme_minimal(base_size = 12) +
                theme(legend.position = "bottom")

              race_plot <- exp1_obj$race_eth %>%
                select(Group = Race, Sample = Unwt_Pct, Population = Wt_Pct) %>%
                pivot_longer(-Group, names_to = "Type", values_to = "Pct")
              race_plot$Type <- factor(race_plot$Type, levels = c("Sample", "Population"))

              p3b <- ggplot(race_plot, aes(x = Group, y = Pct, fill = Type)) +
                geom_col(position = position_dodge(0.8), width = 0.6) +
                scale_fill_manual(values = c("Sample" = "#4DBBD5", "Population" = "#E64B35")) +
                labs(y = "Proportion (%)", x = NULL, fill = NULL,
                     title = "Race/Ethnicity Composition") +
                theme_minimal(base_size = 12) +
                theme(legend.position = "bottom",
                      axis.text.x = element_text(angle = 30, hjust = 1))

              p3 <- p3a + p3b + plot_layout(ncol = 2, guides = "collect") &
                theme(legend.position = "bottom")

              paths <- c(
                fig_exp1_continuous = file.path(out_dir, "fig_exp1_continuous.pdf"),
                fig_exp1_prevalence = file.path(out_dir, "fig_exp1_prevalence.pdf"),
                fig_exp1_composition_age = file.path(out_dir, "fig_exp1_composition_age.pdf"),
                fig_exp1_composition_race = file.path(out_dir, "fig_exp1_composition_race.pdf"),
                fig_exp1_composition = file.path(out_dir, "fig_exp1_composition.pdf")
              )

              ggsave(paths[["fig_exp1_continuous"]], p1, width = 10, height = 4)
              ggsave(paths[["fig_exp1_prevalence"]], p2, width = 6, height = 4)
              ggsave(paths[["fig_exp1_composition_age"]], p3a, width = 6, height = 4)
              ggsave(paths[["fig_exp1_composition_race"]], p3b, width = 8, height = 4)
              ggsave(paths[["fig_exp1_composition"]], p3, width = 12, height = 5)

              paths
            }

            rerun_paths <- render_exp1_figures(rerun_exp1, file.path(scratch_dir, "out"))
            baseline_paths <- render_exp1_figures(baseline_exp1, file.path(scratch_dir, "baseline_out"))

            figure_checks <- list(
              compare_pdf_figure("fig_exp1_continuous", rerun_paths[["fig_exp1_continuous"]], baseline_paths[["fig_exp1_continuous"]]),
              compare_pdf_figure("fig_exp1_prevalence", rerun_paths[["fig_exp1_prevalence"]], baseline_paths[["fig_exp1_prevalence"]]),
              compare_pdf_figure("fig_exp1_composition_age", rerun_paths[["fig_exp1_composition_age"]], baseline_paths[["fig_exp1_composition_age"]]),
              compare_pdf_figure("fig_exp1_composition_race", rerun_paths[["fig_exp1_composition_race"]], baseline_paths[["fig_exp1_composition_race"]]),
              compare_pdf_figure("fig_exp1_composition", rerun_paths[["fig_exp1_composition"]], baseline_paths[["fig_exp1_composition"]])
            )

            bind_rows(figure_checks)
            """
        ),
        code_cell(
            """
            exp1_summary <- summarize_results(c(numeric_checks, figure_checks))
            exp1_summary$results
            """
        ),
    ],
)


write_notebook(
    "02_exp2_repro.ipynb",
    [
        md_cell(
            """
            # Exp 2 Reproducibility Check

            This notebook reruns `code/02_experiment2_evaluation.R` in an isolated scratch workspace
            and compares the rerun numeric outputs against `expected/exp2_evaluation.rds` and the
            curated modeling data in `data/model_df.rds`.
            """
        ),
        code_cell(
            """
            suppressPackageStartupMessages({
              library(survey)
              library(tidyverse)
              library(pROC)
            })

            helper_candidates <- c("repro_utils.R", file.path("notebooks", "repro", "repro_utils.R"))
            helper_path <- helper_candidates[file.exists(helper_candidates)][1]
            if (is.na(helper_path)) {
              stop("repro_utils.R not found.")
            }
            source(helper_path)

            baseline_result_path <- path_in_repo("expected", "exp2_evaluation.rds")
            baseline_model_df_path <- path_in_repo("data", "model_df.rds")
            scratch_dir <- new_scratch("exp2_repro")

            cat("Scratch workspace:", scratch_dir, "\\n")
            cat("Baseline result:", baseline_result_path, "\\n")
            """
        ),
        code_cell(
            """
            run_script_in_scratch(
              "code/02_experiment2_evaluation.R",
              scratch_dir,
              c("data/nhanes_processed.rds", "data/survey_design.rds")
            )

            baseline_exp2 <- readRDS(baseline_result_path)
            rerun_exp2 <- readRDS(file.path(scratch_dir, "results", "exp2_evaluation.rds"))
            baseline_model_df <- readRDS(baseline_model_df_path)
            rerun_model_df <- readRDS(file.path(scratch_dir, "results", "model_df.rds"))
            """
        ),
        code_cell(
            """
            exp2_checks <- list(
              compare_df_tol("model_df", rerun_model_df, baseline_model_df, tol = 1e-12),
              compare_numeric_vec("auc_unwt", rerun_exp2$auc_unwt, baseline_exp2$auc_unwt, tol = 1e-10),
              compare_numeric_vec("auc_wt", rerun_exp2$auc_wt, baseline_exp2$auc_wt, tol = 1e-10),
              compare_numeric_vec("difference", rerun_exp2$difference, baseline_exp2$difference, tol = 1e-10),
              compare_numeric_vec("ci_unwt", rerun_exp2$ci_unwt, baseline_exp2$ci_unwt, tol = 1e-10),
              compare_numeric_vec("ci_wt", rerun_exp2$ci_wt, baseline_exp2$ci_wt, tol = 1e-10),
              compare_exact_scalar("n_boot", rerun_exp2$n_boot, baseline_exp2$n_boot),
              compare_numeric_vec("boot_auc", rerun_exp2$boot_auc, baseline_exp2$boot_auc, tol = 1e-10)
            )

            bind_rows(exp2_checks)
            """
        ),
        code_cell(
            """
            exp2_summary <- summarize_results(exp2_checks)
            exp2_summary$results
            """
        ),
    ],
)


write_notebook(
    "03_exp3_repro.ipynb",
    [
        md_cell(
            """
            # Exp 3 Reproducibility Check

            This notebook reruns `code/03_experiment3_training.R` in an isolated scratch workspace,
            compares the rerun numeric outputs against `expected/exp3_training.rds`, and compares the
            regenerated figures against figures rebuilt from the expected baseline result.
            """
        ),
        code_cell(
            """
            suppressPackageStartupMessages({
              library(survey)
              library(tidyverse)
              library(xgboost)
              library(pROC)
            })

            helper_candidates <- c("repro_utils.R", file.path("notebooks", "repro", "repro_utils.R"))
            helper_path <- helper_candidates[file.exists(helper_candidates)][1]
            if (is.na(helper_path)) {
              stop("repro_utils.R not found.")
            }
            source(helper_path)

            baseline_result_path <- path_in_repo("expected", "exp3_training.rds")
            baseline_model_df_path <- path_in_repo("data", "model_df.rds")
            scratch_dir <- new_scratch("exp3_repro")

            cat("Scratch workspace:", scratch_dir, "\\n")
            cat("Baseline result:", baseline_result_path, "\\n")
            """
        ),
        code_cell(
            """
            run_script_in_scratch(
              "code/03_experiment3_training.R",
              scratch_dir,
              c("data/model_df.rds")
            )

            baseline_exp3 <- readRDS(baseline_result_path)
            rerun_exp3 <- readRDS(file.path(scratch_dir, "results", "exp3_training.rds"))
            model_df <- readRDS(baseline_model_df_path)
            """
        ),
        code_cell(
            """
            exp3_checks <- list(
              compare_named_numeric_list("auc", rerun_exp3$auc, baseline_exp3$auc, tol = 1e-8),
              compare_named_numeric_list("auprc", rerun_exp3$auprc, baseline_exp3$auprc, tol = 1e-8),
              compare_named_numeric_list("ci_auc", rerun_exp3$ci_auc, baseline_exp3$ci_auc, tol = 1e-8),
              compare_named_numeric_list("ci_auprc", rerun_exp3$ci_auprc, baseline_exp3$ci_auprc, tol = 1e-8),
              compare_exact_scalar("n_boot", rerun_exp3$n_boot, baseline_exp3$n_boot),
              compare_numeric_vec("pred_unwt", rerun_exp3$pred_unwt, baseline_exp3$pred_unwt, tol = 1e-8),
              compare_numeric_vec("pred_wt", rerun_exp3$pred_wt, baseline_exp3$pred_wt, tol = 1e-8),
              compare_numeric_vec("boot_auc", as.numeric(rerun_exp3$boot_auc), as.numeric(baseline_exp3$boot_auc), tol = 1e-8),
              compare_numeric_vec("boot_auprc", as.numeric(rerun_exp3$boot_auprc), as.numeric(baseline_exp3$boot_auprc), tol = 1e-8)
            )

            bind_rows(exp3_checks)
            """
        ),
        code_cell(
            """
            source(path_in_repo("code", "helpers_metrics.R"))

            standard_pr <- function(y, pred, n_thresholds = 200) {
              thresholds <- seq(0.01, 0.99, length.out = n_thresholds)
              map_df(thresholds, function(t) {
                pred_class <- as.numeric(pred >= t)
                tp <- sum(y == 1 & pred_class == 1)
                fp <- sum(y == 0 & pred_class == 1)
                fn <- sum(y == 1 & pred_class == 0)
                precision <- ifelse((tp + fp) > 0, tp / (tp + fp), NA)
                recall <- tp / (tp + fn)
                tibble(threshold = t, Precision = precision, Recall = recall)
              }) %>%
                filter(!is.na(Precision))
            }

            weighted_pr <- function(y, pred, weights, n_thresholds = 200) {
              thresholds <- seq(0.01, 0.99, length.out = n_thresholds)
              map_df(thresholds, function(t) {
                pred_class <- as.numeric(pred >= t)
                w_tp <- sum(weights[y == 1 & pred_class == 1])
                w_fp <- sum(weights[y == 0 & pred_class == 1])
                w_fn <- sum(weights[y == 1 & pred_class == 0])
                tibble(
                  threshold = t,
                  Precision = ifelse((w_tp + w_fp) > 0, w_tp / (w_tp + w_fp), NA),
                  Recall = w_tp / (w_tp + w_fn)
                )
              }) %>%
                filter(!is.na(Precision))
            }

            render_exp3_figures <- function(exp3_obj, model_df, out_dir) {
              ensure_dir(out_dir)

              y <- model_df$diabetes
              weights <- model_df$WTMEC2YR
              pred_unwt <- exp3_obj$pred_unwt
              pred_wt <- exp3_obj$pred_wt

              auc_unwt_model_unwt_eval <- exp3_obj$auc$unwt_unwt
              auc_wt_model_unwt_eval <- exp3_obj$auc$wt_unwt
              auc_unwt_model_wt_eval <- exp3_obj$auc$unwt_wt
              auc_wt_model_wt_eval <- exp3_obj$auc$wt_wt

              auprc_unwt_model_unwt_eval <- exp3_obj$auprc$unwt_unwt
              auprc_wt_model_unwt_eval <- exp3_obj$auprc$wt_unwt
              auprc_unwt_model_wt_eval <- exp3_obj$auprc$unwt_wt
              auprc_wt_model_wt_eval <- exp3_obj$auprc$wt_wt

              roc_unwt_model <- roc(y, pred_unwt, quiet = TRUE)
              roc_wt_model <- roc(y, pred_wt, quiet = TRUE)
              pr_unwt_std <- standard_pr(y, pred_unwt)
              pr_wt_std <- standard_pr(y, pred_wt)
              pr_unwt_wt <- weighted_pr(y, pred_unwt, weights)
              pr_wt_wt <- weighted_pr(y, pred_wt, weights)

              roc_path <- file.path(out_dir, "fig3_roc_curves.pdf")
              pr_path <- file.path(out_dir, "fig4_pr_curves.pdf")

              pdf(roc_path, width = 12, height = 5)
              par(mfrow = c(1, 2))
              plot(roc_unwt_model, col = "blue", lwd = 2, main = "(a) Standard Evaluation", legacy.axes = TRUE)
              plot(roc_wt_model, col = "red", lwd = 2, add = TRUE)
              legend("bottomright", legend = c(sprintf("Unweighted XGB (AUC=%.3f)", auc_unwt_model_unwt_eval),
                     sprintf("Weighted XGB (AUC=%.3f)", auc_wt_model_unwt_eval)), col = c("blue", "red"), lwd = 2, cex = 0.8)
              plot(roc_unwt_model, col = "blue", lwd = 2, main = "(b) Standard ROC Curves with wAUC Labels", legacy.axes = TRUE)
              plot(roc_wt_model, col = "red", lwd = 2, add = TRUE)
              legend("bottomright", legend = c(sprintf("Unweighted XGB (wAUC=%.3f)", auc_unwt_model_wt_eval),
                     sprintf("Weighted XGB (wAUC=%.3f)", auc_wt_model_wt_eval)), col = c("blue", "red"), lwd = 2, cex = 0.8)
              dev.off()

              pdf(pr_path, width = 12, height = 5)
              par(mfrow = c(1, 2))
              plot(pr_unwt_std$Recall, pr_unwt_std$Precision, type = "l", col = "blue", lwd = 2,
                   xlim = c(0, 1), ylim = c(0, 1), xlab = "Recall", ylab = "Precision", main = "(a) Standard Evaluation")
              lines(pr_wt_std$Recall, pr_wt_std$Precision, col = "red", lwd = 2)
              legend("topright", legend = c(sprintf("Unweighted XGB (AUPRC=%.3f)", auprc_unwt_model_unwt_eval),
                     sprintf("Weighted XGB (AUPRC=%.3f)", auprc_wt_model_unwt_eval)), col = c("blue", "red"), lwd = 2, cex = 0.8)
              plot(pr_unwt_wt$Recall, pr_unwt_wt$Precision, type = "l", col = "blue", lwd = 2,
                   xlim = c(0, 1), ylim = c(0, 1), xlab = "Recall", ylab = "Precision", main = "(b) Survey-Weighted Evaluation")
              lines(pr_wt_wt$Recall, pr_wt_wt$Precision, col = "red", lwd = 2)
              legend("topright", legend = c(sprintf("Unweighted XGB (wAUPRC=%.3f)", auprc_unwt_model_wt_eval),
                     sprintf("Weighted XGB (wAUPRC=%.3f)", auprc_wt_model_wt_eval)), col = c("blue", "red"), lwd = 2, cex = 0.8)
              dev.off()

              c(fig3_roc_curves = roc_path, fig4_pr_curves = pr_path)
            }

            rerun_paths <- render_exp3_figures(rerun_exp3, model_df, file.path(scratch_dir, "out"))
            baseline_paths <- render_exp3_figures(baseline_exp3, model_df, file.path(scratch_dir, "baseline_out"))

            figure_checks <- list(
              compare_pdf_figure("fig3_roc_curves", rerun_paths[["fig3_roc_curves"]], baseline_paths[["fig3_roc_curves"]]),
              compare_pdf_figure("fig4_pr_curves", rerun_paths[["fig4_pr_curves"]], baseline_paths[["fig4_pr_curves"]])
            )

            bind_rows(figure_checks)
            """
        ),
        code_cell(
            """
            exp3_summary <- summarize_results(c(exp3_checks, figure_checks))
            exp3_summary$results
            """
        ),
    ],
)


write_notebook(
    "04_exp4_repro.ipynb",
    [
        md_cell(
            """
            # Exp 4 Reproducibility Check

            This notebook reruns `code/04_experiment4_cv_factorial.R` in an isolated scratch
            workspace, compares the rerun fold structure and numeric outputs against
            `expected/exp4_cv_factorial.rds`, and compares the regenerated AUC plot against
            the same plot rebuilt from the expected baseline result.
            """
        ),
        code_cell(
            """
            suppressPackageStartupMessages({
              library(survey)
              library(tidyverse)
              library(xgboost)
              library(pROC)
            })

            helper_candidates <- c("repro_utils.R", file.path("notebooks", "repro", "repro_utils.R"))
            helper_path <- helper_candidates[file.exists(helper_candidates)][1]
            if (is.na(helper_path)) {
              stop("repro_utils.R not found.")
            }
            source(helper_path)

            baseline_result_path <- path_in_repo("expected", "exp4_cv_factorial.rds")
            scratch_dir <- new_scratch("exp4_repro")

            cat("Scratch workspace:", scratch_dir, "\\n")
            cat("Baseline result:", baseline_result_path, "\\n")
            """
        ),
        code_cell(
            """
            run_script_in_scratch(
              "code/04_experiment4_cv_factorial.R",
              scratch_dir,
              c("data/model_df.rds")
            )

            baseline_exp4 <- readRDS(baseline_result_path)
            rerun_exp4 <- readRDS(file.path(scratch_dir, "results", "exp4_cv_factorial.rds"))
            """
        ),
        code_cell(
            """
            params_to_df <- function(exp4_obj) {
              tibble(
                name = c(
                  "n_folds",
                  "n_repeats",
                  "nrounds",
                  paste0("xgb_params.", names(exp4_obj$params$xgb_params))
                ),
                value = c(
                  as.character(exp4_obj$params$n_folds),
                  as.character(exp4_obj$params$n_repeats),
                  as.character(exp4_obj$params$nrounds),
                  vapply(exp4_obj$params$xgb_params, as.character, character(1))
                )
              )
            }

            fold_profile <- function(exp4_obj) {
              exp4_obj$results %>%
                distinct(cv_type, repeat_id, fold_id, n_test, n_pos) %>%
                arrange(cv_type, repeat_id, fold_id)
            }

            ordered_results <- function(exp4_obj) {
              exp4_obj$results %>%
                arrange(cv_type, repeat_id, fold_id, train_type, eval_type)
            }

            ordered_summary <- function(exp4_obj) {
              exp4_obj$summary_stats %>%
                arrange(cv_type, train_type, eval_type)
            }

            exp4_checks <- list(
              compare_df_exact("exp4_params", params_to_df(rerun_exp4), params_to_df(baseline_exp4)),
              compare_df_exact("exp4_fold_profile", fold_profile(rerun_exp4), fold_profile(baseline_exp4)),
              compare_df_tol("exp4_results", ordered_results(rerun_exp4), ordered_results(baseline_exp4), tol = 1e-12),
              compare_df_tol("exp4_summary_stats", ordered_summary(rerun_exp4), ordered_summary(baseline_exp4), tol = 1e-12)
            )

            bind_rows(exp4_checks)
            """
        ),
        code_cell(
            """
            build_exp4_auc_plot <- function(exp4_obj) {
              plot_df <- exp4_obj$results %>%
                mutate(condition = paste0(train_type, " Train\\n", eval_type, " Eval"))

              ggplot(plot_df, aes(x = condition, y = auc, fill = cv_type)) +
                geom_violin(position = position_dodge(0.8), alpha = 0.6, trim = FALSE) +
                geom_boxplot(position = position_dodge(0.8), width = 0.15, outlier.size = 0.8) +
                scale_fill_manual(values = c("Random" = "#4393C3", "PSU" = "#D6604D"),
                                  name = "CV Type") +
                labs(x = NULL, y = "AUC",
                     title = "Cross-Validation Type Effect on AUC Estimates") +
                theme_bw(base_size = 12) +
                theme(axis.text.x = element_text(size = 9),
                      legend.position = "top")
            }

            rerun_plot_path <- file.path(scratch_dir, "out", "fig_exp4_cv_type_auc.pdf")
            baseline_plot_path <- file.path(scratch_dir, "baseline_out", "fig_exp4_cv_type_auc.pdf")

            ggsave(rerun_plot_path, build_exp4_auc_plot(rerun_exp4), width = 8, height = 5)
            ggsave(baseline_plot_path, build_exp4_auc_plot(baseline_exp4), width = 8, height = 5)

            figure_checks <- list(
              compare_pdf_figure("fig_exp4_cv_type_auc", rerun_plot_path, baseline_plot_path)
            )

            bind_rows(figure_checks)
            """
        ),
        code_cell(
            """
            exp4_summary <- summarize_results(c(exp4_checks, figure_checks))
            exp4_summary$results
            """
        ),
    ],
)
