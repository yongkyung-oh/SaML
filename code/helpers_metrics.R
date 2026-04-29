# Shared metrics helpers for the public release scripts.

#' Survey-weighted AUC using a rank-based Horvitz-Thompson estimator
weighted_auc_fast <- function(y, pred, weights) {
  if (length(y) != length(pred) || length(y) != length(weights)) {
    stop("y, pred, and weights must have the same length.")
  }

  if (is.factor(y)) {
    y <- if (all(levels(y) %in% c("No", "Yes"))) {
      as.integer(y == "Yes")
    } else {
      as.integer(as.character(y))
    }
  } else {
    y <- as.integer(y)
  }

  keep <- !is.na(y)
  y <- y[keep]
  pred <- pred[keep]
  weights <- weights[keep]

  if (anyNA(pred) || anyNA(weights)) {
    stop("pred and weights must not contain missing values.")
  }

  if (!all(y %in% c(0L, 1L))) {
    stop("y must be binary (0/1, FALSE/TRUE, or factor with No/Yes levels).")
  }

  w_pos_total <- sum(weights[y == 1L])
  w_neg_total <- sum(weights[y == 0L])

  if (w_pos_total == 0 || w_neg_total == 0) {
    return(NA_real_)
  }

  ord <- order(pred)
  y_sorted <- y[ord]
  pred_sorted <- pred[ord]
  weights_sorted <- weights[ord]

  tie_id <- cumsum(c(TRUE, diff(pred_sorted) != 0))
  neg_weights <- weights_sorted * (y_sorted == 0L)
  neg_group_weight <- as.vector(rowsum(neg_weights, tie_id, reorder = FALSE))
  neg_prefix_strict <- cumsum(neg_group_weight) - neg_group_weight

  pos_mask <- (y_sorted == 1L)
  pos_weights <- weights_sorted[pos_mask]
  pos_tie_id <- tie_id[pos_mask]

  contribution <- pos_weights * (
    neg_prefix_strict[pos_tie_id] + 0.5 * neg_group_weight[pos_tie_id]
  )

  sum(contribution) / (w_pos_total * w_neg_total)
}

weighted_auc <- weighted_auc_fast
