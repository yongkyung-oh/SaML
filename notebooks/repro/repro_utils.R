suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

helper_path <- tryCatch(
  normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = TRUE),
  error = function(e) NA_character_
)

if (is.na(helper_path) || !nzchar(helper_path)) {
  candidates <- c(
    file.path(getwd(), "repro_utils.R"),
    file.path(getwd(), "notebooks", "repro", "repro_utils.R")
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0) {
    stop("Could not locate repro_utils.R from the current working directory.")
  }
  helper_path <- normalizePath(existing[[1]], winslash = "/", mustWork = TRUE)
}

helper_dir <- dirname(helper_path)
repo_root <- normalizePath(file.path(helper_dir, "..", ".."), winslash = "/", mustWork = TRUE)

path_in_repo <- function(...) {
  normalizePath(file.path(repo_root, ...), winslash = "/", mustWork = FALSE)
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

new_scratch <- function(tag) {
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  scratch_dir <- file.path(tempdir(), paste0(tag, "_", stamp))
  ensure_dir(scratch_dir)
  ensure_dir(file.path(scratch_dir, "code"))
  ensure_dir(file.path(scratch_dir, "data"))
  ensure_dir(file.path(scratch_dir, "results"))
  ensure_dir(file.path(scratch_dir, "out"))
  ensure_dir(file.path(scratch_dir, "baseline_out"))
  normalizePath(scratch_dir, winslash = "/", mustWork = TRUE)
}

copy_repo_file <- function(repo_rel, dest_path) {
  src <- path_in_repo(repo_rel)
  if (!file.exists(src)) {
    stop(sprintf("Missing repo file: %s", src))
  }
  ensure_dir(dirname(dest_path))
  ok <- file.copy(src, dest_path, overwrite = TRUE)
  if (!ok) {
    stop(sprintf("Failed to copy %s to %s", src, dest_path))
  }
}

copy_repo_inputs <- function(scratch_dir, repo_inputs) {
  for (repo_input in repo_inputs) {
    dest <- file.path(scratch_dir, repo_input)
    copy_repo_file(repo_input, dest)
  }
}

run_script_in_scratch <- function(script_rel, scratch_dir, input_files) {
  copy_repo_inputs(scratch_dir, input_files)
  copy_repo_file("code/public_paths.R", file.path(scratch_dir, "code", "public_paths.R"))
  copy_repo_file("code/helpers_metrics.R", file.path(scratch_dir, "code", "helpers_metrics.R"))
  copy_repo_file(script_rel, file.path(scratch_dir, script_rel))

  old_wd <- setwd(scratch_dir)
  on.exit(setwd(old_wd), add = TRUE)

  env <- new.env(parent = globalenv())
  sys.source(file.path(scratch_dir, script_rel), envir = env)
  invisible(env)
}

normalize_df <- function(df) {
  if (inherits(df, "tbl_df")) {
    df <- as.data.frame(df)
  }
  rownames(df) <- NULL
  df
}

result_row <- function(artifact, check, pass, detail) {
  tibble(
    artifact = artifact,
    check = check,
    status = if (isTRUE(pass)) "PASS" else "FAIL",
    detail = detail
  )
}

compare_exact_scalar <- function(name, actual, expected) {
  pass <- identical(actual, expected)
  result_row(
    artifact = name,
    check = "exact",
    pass = pass,
    detail = sprintf("baseline=%s; rerun=%s", expected, actual)
  )
}

compare_numeric_vec <- function(name, actual, expected, tol = 1e-8) {
  actual_num <- as.numeric(actual)
  expected_num <- as.numeric(expected)

  if (length(actual_num) != length(expected_num)) {
    return(result_row(name, "numeric", FALSE, sprintf("length mismatch: %d vs %d", length(expected_num), length(actual_num))))
  }

  diff <- abs(actual_num - expected_num)
  diff[is.na(diff)] <- 0
  max_diff <- if (length(diff) == 0) 0 else max(diff)

  result_row(
    artifact = name,
    check = "numeric",
    pass = max_diff <= tol,
    detail = sprintf("max abs diff = %.12g (tol=%.1e)", max_diff, tol)
  )
}

compare_named_numeric_list <- function(name, actual, expected, tol = 1e-8) {
  actual_vec <- unlist(actual, use.names = TRUE)
  expected_vec <- unlist(expected, use.names = TRUE)

  if (!identical(names(actual_vec), names(expected_vec))) {
    return(result_row(name, "numeric", FALSE, "named elements differ"))
  }

  compare_numeric_vec(name, actual_vec, expected_vec, tol = tol)
}

compare_df_exact <- function(name, actual, expected) {
  actual_df <- normalize_df(actual)
  expected_df <- normalize_df(expected)

  result_row(
    artifact = name,
    check = "table",
    pass = identical(actual_df, expected_df),
    detail = if (identical(actual_df, expected_df)) "exact match" else "data frame differs"
  )
}

compare_df_tol <- function(name, actual, expected, tol = 1e-8) {
  actual_df <- normalize_df(actual)
  expected_df <- normalize_df(expected)

  if (!identical(names(actual_df), names(expected_df))) {
    return(result_row(name, "table", FALSE, "column names differ"))
  }

  if (nrow(actual_df) != nrow(expected_df)) {
    return(result_row(name, "table", FALSE, sprintf("row count mismatch: %d vs %d", nrow(expected_df), nrow(actual_df))))
  }

  for (col in names(actual_df)) {
    actual_col <- actual_df[[col]]
    expected_col <- expected_df[[col]]

    if (is.numeric(actual_col) || is.integer(actual_col)) {
      cmp <- compare_numeric_vec(col, actual_col, expected_col, tol = tol)
      if (cmp$status == "FAIL") {
        return(result_row(name, "table", FALSE, sprintf("%s -> %s", col, cmp$detail[[1]])))
      }
    } else if (!identical(as.character(actual_col), as.character(expected_col))) {
      return(result_row(name, "table", FALSE, sprintf("%s differs", col)))
    }
  }

  result_row(name, "table", TRUE, sprintf("all columns within tolerance %.1e", tol))
}

render_pdf_png_hash <- function(pdf_path, dpi = 150) {
  if (!nzchar(Sys.which("pdftoppm"))) {
    stop("pdftoppm is not available on PATH.")
  }

  pdf_path <- normalizePath(pdf_path, winslash = "/", mustWork = TRUE)
  render_dir <- tempfile("pdf_render_")
  dir.create(render_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(render_dir, recursive = TRUE), add = TRUE)

  prefix <- file.path(render_dir, "page")
  args <- c("-png", "-singlefile", "-r", as.character(dpi), pdf_path, prefix)
  system2("pdftoppm", args = args, stdout = TRUE, stderr = TRUE)

  png_path <- paste0(prefix, ".png")
  if (!file.exists(png_path)) {
    stop(sprintf("Failed to render %s to PNG.", pdf_path))
  }

  unname(tools::md5sum(png_path)[[1]])
}

compare_pdf_figure <- function(name, rerun_pdf, baseline_pdf, dpi = 150) {
  rerun_hash <- render_pdf_png_hash(rerun_pdf, dpi = dpi)
  baseline_hash <- render_pdf_png_hash(baseline_pdf, dpi = dpi)

  result_row(
    artifact = name,
    check = "figure",
    pass = identical(rerun_hash, baseline_hash),
    detail = sprintf("baseline=%s; rerun=%s", baseline_hash, rerun_hash)
  )
}

summarize_results <- function(results) {
  summary_tbl <- bind_rows(results)
  print(summary_tbl, n = nrow(summary_tbl))
  overall <- all(summary_tbl$status == "PASS")
  cat("\nOverall status:", if (overall) "PASS" else "FAIL", "\n")
  list(results = summary_tbl, overall = overall)
}
