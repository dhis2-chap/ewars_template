#!/usr/bin/env Rscript
#
# Entry point for the test suite.
#
#   Rscript tests/run_tests.R      run against the local R installation
#   make test                      the same thing
#   make test-docker               run inside the model image, which has the
#                                  INLA solver and so also runs the end-to-end
#                                  prediction test
#
# Tests that need the INLA solver binary skip themselves when it is missing,
# so a local run exercises everything except the full model fit.

if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("testthat is required: install.packages('testthat')", call. = FALSE)
}

script_dir <- local({
  file_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_argument) == 0) {
    "tests"
  } else {
    dirname(normalizePath(sub("^--file=", "", file_argument[1])))
  }
})

testthat::test_dir(file.path(script_dir, "testthat"), stop_on_failure = TRUE)
