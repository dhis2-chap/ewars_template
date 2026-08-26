# Shared setup for the EWARS test suite.
#
# predict.R is a plain script rather than a package: it attaches its libraries,
# sources lib.R through a relative path, and ends with a commandArgs() block
# that starts a real prediction when arguments are present. Sourcing it here
# from the repository root exposes every function under test, with the
# command-line block neutralised so the suite can never kick off a run of its
# own.

find_repo_root <- function(start = getwd()) {
  path <- normalizePath(start, mustWork = TRUE)
  while (!file.exists(file.path(path, "MLproject"))) {
    parent <- dirname(path)
    if (identical(parent, path)) {
      stop("could not locate the repository root (no MLproject at or above ", start, ")")
    }
    path <- parent
  }
  path
}

repo_root <- find_repo_root()

repo_path <- function(...) file.path(repo_root, ...)

local({
  previous <- setwd(repo_root)
  on.exit(setwd(previous), add = TRUE)

  scripts <- new.env(parent = globalenv())
  scripts$commandArgs <- function(trailingOnly = FALSE) character(0)
  suppressPackageStartupMessages(
    sys.source(repo_path("predict.R"), envir = scripts)
  )
  rm("commandArgs", envir = scripts)
  list2env(as.list(scripts, all.names = TRUE), envir = globalenv())
})

# INLA ships its solver as a platform-specific binary alongside the R package,
# and the package installs cleanly even where that binary is not built. Test
# for the binary rather than for the package, so the integration test skips on
# a developer machine and runs inside the model image.
inla_solver_available <- function() {
  solver <- tryCatch(INLA::inla.getOption("inla.call"), error = function(e) NULL)
  !is.null(solver) && nzchar(solver) && file.exists(solver)
}

# The scripts print progress to stdout on every call. Swallow it so a test run
# stays readable; testthat still reports failures and warnings as normal.
quietly <- function(expr) {
  result <- NULL
  invisible(utils::capture.output(result <- expr))
  result
}

# The monthly example data is the fixture for anything that needs a realistic
# panel: 23 locations, 2001-01 to 2016-12, with rainfall and mean_temperature.
monthly_training_data <- function() {
  read.csv(repo_path("example_data_monthly", "training_data.csv"))
}

basis_matrix <- function(model_data) {
  columns <- grep("^basis_", names(model_data), value = TRUE)
  matrix <- as.matrix(model_data[, columns, drop = FALSE])
  matrix[stats::complete.cases(matrix), , drop = FALSE]
}
