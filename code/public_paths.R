helper_path <- tryCatch(
  normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = TRUE),
  error = function(e) NA_character_
)

if (is.na(helper_path) || !nzchar(helper_path)) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    helper_path <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)
  }
}

if (is.na(helper_path) || !nzchar(helper_path)) {
  candidates <- c(
    file.path(getwd(), "code", "public_paths.R"),
    file.path(getwd(), "public_paths.R")
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0) {
    stop("Could not locate code/public_paths.R from the current working directory.")
  }
  helper_path <- normalizePath(existing[[1]], winslash = "/", mustWork = TRUE)
}

code_dir <- dirname(helper_path)
repo_root <- normalizePath(file.path(code_dir, ".."), winslash = "/", mustWork = TRUE)

repo_path <- function(...) {
  normalizePath(file.path(repo_root, ...), winslash = "/", mustWork = FALSE)
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

data_path <- function(...) {
  repo_path("data", ...)
}

expected_path <- function(...) {
  repo_path("expected", ...)
}

results_dir <- function() {
  ensure_dir(repo_path("results"))
}

results_path <- function(...) {
  repo_path("results", ...)
}
