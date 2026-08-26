# parse_model_configuration reads the YAML that CHAP writes for a run. Every
# field is optional, and predict_chap falls back to its own defaults for
# anything missing, so the parser has to report absence rather than guess.

write_config <- function(text) {
  path <- tempfile(fileext = ".yaml")
  writeLines(text, path)
  path
}

test_that("a full configuration round-trips", {
  path <- write_config(c(
    "additional_continuous_covariates:",
    "  - rainfall",
    "  - mean_temperature",
    "user_option_values:",
    "  n_lags: 3",
    "  precision: 1",
    "  region_seasonal: false"
  ))

  config <- quietly(parse_model_configuration(path))

  expect_equal(config$additional_continuous_covariates, c("rainfall", "mean_temperature"))
  expect_equal(config$user_option_values$n_lags, 3)
  expect_equal(config$user_option_values$precision, 1)
  expect_false(config$user_option_values$region_seasonal)
})

test_that("the shipped example configuration parses", {
  config <- quietly(parse_model_configuration(repo_path("example_config.yaml")))

  expect_equal(config$additional_continuous_covariates, c("rainfall", "mean_temperature"))
  expect_equal(config$user_option_values$n_lags, 3)
})

test_that("n_lags is accepted both as a scalar and as a list", {
  scalar <- quietly(parse_model_configuration(write_config(c(
    "user_option_values:", "  n_lags: 3"
  ))))
  per_covariate <- quietly(parse_model_configuration(write_config(c(
    "user_option_values:", "  n_lags: [3, 4]"
  ))))

  expect_equal(scalar$user_option_values$n_lags, 3)
  expect_equal(per_covariate$user_option_values$n_lags, c(3, 4))
})

test_that("missing sections come back empty rather than as NULL surprises", {
  empty <- quietly(parse_model_configuration(write_config("additional_continuous_covariates: []")))

  expect_length(empty$user_option_values, 0)

  partial <- quietly(parse_model_configuration(write_config(c(
    "user_option_values:", "  n_lags: 3"
  ))))

  expect_equal(partial$additional_continuous_covariates, character())
  # predict_chap reads these with is.null() checks, so absence has to stay
  # absent instead of arriving as a default the caller cannot distinguish.
  expect_null(partial$user_option_values$precision)
  expect_null(partial$user_option_values$region_seasonal)
})
