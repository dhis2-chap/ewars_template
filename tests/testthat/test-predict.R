# End-to-end run of predict_chap over the monthly example data. This needs the
# INLA solver binary, so it runs inside the model image and skips elsewhere.

test_that("predict_chap writes samples for every period without a case count", {
  skip_if_not(inla_solver_available(), "INLA solver binary not available")

  historic_fn <- repo_path("example_data_monthly", "historic_data.csv")
  future_fn <- repo_path("example_data_monthly", "future_data.csv")
  predictions_fn <- tempfile(fileext = ".csv")

  quietly(predict_chap(
    model_fn = tempfile(),
    hist_fn = historic_fn,
    future_fn = future_fn,
    preds_fn = predictions_fn,
    config_fn = repo_path("example_config.yaml")
  ))

  expect_true(file.exists(predictions_fn))
  predictions <- read.csv(predictions_fn)

  historic <- read.csv(historic_fn)
  future <- read.csv(future_fn)
  # predict_chap forecasts every row with a missing case count, which is the
  # future window plus any gaps in the historic series.
  expect_equal(nrow(predictions), sum(is.na(historic$Cases)) + nrow(future))

  expect_equal(names(predictions)[1:2], c("time_period", "location"))
  expect_equal(sum(grepl("^sample_", names(predictions))), 1000)

  samples <- as.matrix(predictions[, grep("^sample_", names(predictions))])
  expect_true(all(is.finite(samples)))
  expect_true(all(samples >= 0))
  expect_true(all(samples == round(samples)))

  # Every future period and location must be represented.
  expect_true(all(unique(future$time_period) %in% predictions$time_period))
  expect_true(all(unique(future$location) %in% predictions$location))
})

test_that("predict_chap falls back to its built-in defaults without a config", {
  skip_if_not(inla_solver_available(), "INLA solver binary not available")

  predictions_fn <- tempfile(fileext = ".csv")

  quietly(predict_chap(
    model_fn = tempfile(),
    hist_fn = repo_path("example_data_monthly", "historic_data.csv"),
    future_fn = repo_path("example_data_monthly", "future_data.csv"),
    preds_fn = predictions_fn
  ))

  expect_true(file.exists(predictions_fn))
  expect_gt(nrow(read.csv(predictions_fn)), 0)
})
