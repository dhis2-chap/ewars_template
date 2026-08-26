# generate_lagged_model builds the distributed-lag crossbasis and the INLA
# formula. The crossbasis is where the model is most easily broken in a way
# that only shows up much later, as a solver crash rather than a bad number,
# so these tests assert its algebraic properties directly.

covariates <- c("rainfall", "mean_temperature")

lagged_data <- function(df, n_lags, region_seasonal = FALSE) {
  quietly(generate_lagged_model(df, covariates, n_lags, region_seasonal))$data
}

lagged_formula_text <- function(df, n_lags, region_seasonal = FALSE) {
  generated <- quietly(generate_lagged_model(df, covariates, n_lags, region_seasonal))
  paste(deparse(generated$formula), collapse = " ")
}

test_that("the crossbasis is full column rank across the supported lag range", {
  df <- monthly_training_data()

  # The lag basis is evaluated at only n_lags distinct points, so it can carry
  # at most n_lags independent columns. Asking for more makes the design matrix
  # rank deficient; with a weak prior on the fixed effects the posterior
  # precision matrix then goes singular and INLA aborts with
  # "GMRFLib_tabulate_Qfunc_core: Assertion `arg->Q->a[0] >= 0.0' failed".
  # See https://dhis2.atlassian.net/browse/CLIM-929.
  for (n_lags in 2:8) {
    basis <- basis_matrix(lagged_data(df, n_lags))

    expect_gt(ncol(basis), 0)
    expect_equal(
      qr(basis)$rank, ncol(basis),
      label = paste0("crossbasis rank at n_lags = ", n_lags),
      expected.label = paste0(ncol(basis), " (its column count)")
    )
  }
})

test_that("the crossbasis stays well conditioned at the default lag", {
  basis <- basis_matrix(lagged_data(monthly_training_data(), 3))

  singular_values <- svd(scale(basis))$d
  condition_number <- singular_values[1] / singular_values[length(singular_values)]

  # A rank-deficient basis pushes this past 1e15. Anything in single digits is
  # comfortably invertible; the bound is loose on purpose.
  expect_lt(condition_number, 1e3)
})

test_that("each covariate contributes its own named block of basis columns", {
  df <- monthly_training_data()
  model_data <- lagged_data(df, 3)
  columns <- grep("^basis_", names(model_data), value = TRUE)

  for (covariate in covariates) {
    expect_gt(length(grep(paste0("^basis_", covariate, "\\."), columns)), 0)
  }
  # Original columns survive; the basis is added alongside, not in place of.
  expect_true(all(names(df) %in% names(model_data)))
  expect_equal(nrow(model_data), nrow(df))
})

test_that("a single n_lags value is broadcast across covariates", {
  df <- monthly_training_data()

  expect_equal(
    basis_matrix(lagged_data(df, 3)),
    basis_matrix(lagged_data(df, c(3, 3)))
  )
})

test_that("per-covariate lags produce differently sized blocks", {
  model_data <- lagged_data(monthly_training_data(), c(3, 6))
  columns <- grep("^basis_", names(model_data), value = TRUE)

  rainfall <- grep("^basis_rainfall\\.", columns, value = TRUE)
  temperature <- grep("^basis_mean_temperature\\.", columns, value = TRUE)

  expect_gt(length(temperature), length(rainfall))
  expect_equal(qr(basis_matrix(model_data))$rank, length(columns))
})

test_that("a mismatched n_lags length is rejected", {
  expect_error(
    quietly(generate_lagged_model(monthly_training_data(), covariates, c(3, 4, 5), FALSE)),
    "nlag must have length 1 or the same length as the number of covariates"
  )
})

test_that("the formula carries every basis column and the structured terms", {
  df <- monthly_training_data()
  formula_text <- lagged_formula_text(df, 3)
  columns <- grep("^basis_", names(lagged_data(df, 3)), value = TRUE)

  for (column in columns) {
    expect_true(grepl(column, formula_text, fixed = TRUE))
  }
  expect_true(grepl("f(ID_spat, model = \"iid\", replicate = ID_year)", formula_text, fixed = TRUE))
  expect_true(grepl("ID_time_cyclic", formula_text, fixed = TRUE))
  expect_false(grepl("ID_time_cyclic2", formula_text, fixed = TRUE))
})

test_that("region_seasonal adds the per-region seasonal term", {
  formula_text <- lagged_formula_text(monthly_training_data(), 3, region_seasonal = TRUE)

  expect_true(grepl("ID_time_cyclic2", formula_text, fixed = TRUE))
  expect_true(grepl("replicate = ID_spat", formula_text, fixed = TRUE))
})

test_that("the covariate-free model has no basis columns and leaves data untouched", {
  df <- monthly_training_data()
  generated <- quietly(generate_bacic_model(df, character(), 3, FALSE))
  formula_text <- paste(deparse(generated$formula), collapse = " ")

  expect_identical(generated$data, df)
  expect_false(grepl("basis_", formula_text, fixed = TRUE))
  expect_true(grepl("ID_time_cyclic", formula_text, fixed = TRUE))
})
