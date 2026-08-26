# lib.R rotates the calendar so the most recent observed period lands in the
# middle of the year (month 6, week 26). The cyclic RW1 seasonal term is then
# never asked to wrap across the boundary between observed and forecast
# periods, which is where a wrap would do the most damage.

test_that("offset_years_and_months moves the last observed month to month 6", {
  df <- data.frame(
    month = c(1:12, 1:3),
    ID_year = c(rep(2020L, 12), rep(2021L, 3)),
    Cases = c(rep(5, 12), 5, NA, NA)
  )

  out <- offset_years_and_months(df)

  # 2021-01 is the last row with a case count, so it is the one to centre.
  last_observed <- which(!is.na(df$Cases))[sum(!is.na(df$Cases))]
  expect_equal(out$month[last_observed], 6)
})

test_that("offset_years_and_months keeps months in range and rolls the year over", {
  df <- data.frame(
    month = 1:12,
    ID_year = rep(2020L, 12),
    Cases = rep(5, 12)
  )

  out <- offset_years_and_months(df)

  expect_true(all(out$month >= 1 & out$month <= 12))
  # last observed month is 12, so month_diff is 6 and everything from July on
  # spills into the following year.
  expect_equal(out$month, c(7:12, 1:6))
  expect_equal(out$ID_year, c(rep(2020L, 6), rep(2021L, 6)))
})

test_that("offset_years_and_weeks moves the last observed week to week 26", {
  df <- data.frame(
    week = c(1:52, 1:4),
    ID_year = c(rep(2020L, 52), rep(2021L, 4)),
    Cases = c(rep(5, 52), 5, NA, NA, NA)
  )

  out <- offset_years_and_weeks(df)

  last_observed <- which(!is.na(df$Cases))[sum(!is.na(df$Cases))]
  expect_equal(out$week[last_observed], 26)
  expect_true(all(out$week >= 1 & out$week <= 52))
})

test_that("the offset ignores forecast rows when finding the last observation", {
  observed_only <- data.frame(
    month = 1:6,
    ID_year = rep(2020L, 6),
    Cases = rep(5, 6)
  )
  with_forecast <- rbind(
    observed_only,
    data.frame(month = 7:9, ID_year = rep(2020L, 3), Cases = rep(NA_real_, 3))
  )

  # Appending rows with no case count must not change how the observed rows
  # are shifted: the forecast rows are exactly what the model has to predict.
  expect_equal(
    offset_years_and_months(with_forecast)$month[1:6],
    offset_years_and_months(observed_only)$month
  )
})
