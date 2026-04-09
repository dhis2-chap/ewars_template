library(yaml)
library(jsonlite)
library(INLA)
library(dlnm)
library(dplyr)
source("scripts/lib.R")

library(sf)
library(spdep)

# --- Column adapter: rename CHAP standard names to internal model names ---
apply_adapters <- function(df) {
  rename_map <- c(
    "disease_cases" = "Cases",
    "population" = "E",
    "location" = "ID_spat",
    "year" = "ID_year"
  )
  for (from in names(rename_map)) {
    to <- rename_map[[from]]
    if (from %in% colnames(df) && !(to %in% colnames(df))) {
      names(df)[names(df) == from] <- to
    }
  }
  return(df)
}

# --- Config parsing (flat YAML from chapkit) ---
parse_config <- function(config_path) {
  if (!file.exists(config_path)) {
    return(list(
      n_lags = 3,
      precision = 0.01,
      additional_continuous_covariates = character()
    ))
  }
  config <- yaml.load_file(config_path)
  list(
    n_lags = if (!is.null(config$n_lags)) config$n_lags else 3,
    precision = if (!is.null(config$precision)) config$precision else 0.01,
    additional_continuous_covariates = if (!is.null(config$additional_continuous_covariates)) {
      config$additional_continuous_covariates
    } else {
      character()
    }
  )
}

# --- Model generation functions ---
generate_bacic_model <- function(df, covariates, nlag) {
  formula_str <- paste(
    "Cases ~ 1 +",
    "f(ID_spat, model='iid', replicate=ID_year) +",
    "f(ID_time_cyclic, model='rw1', cyclic=TRUE, scale.model=TRUE)"
  )
  model_formula <- as.formula(formula_str)
  return(list(formula = model_formula, data = df))
}

generate_lagged_model <- function(df, covariates, nlag) {
  basis_list <- list()

  for (cov in covariates) {
    var_data <- df[[cov]]
    basis <- crossbasis(
      var_data, lag = nlag,
      argvar = list(fun = "ns", knots = equalknots(var_data, 2)),
      arglag = list(fun = "ns", knots = nlag / 2),
      group = df$ID_spat
    )
    basis_name <- paste0("basis_", cov)
    colnames(basis) <- paste0(basis_name, ".", colnames(basis))
    basis_list[[basis_name]] <- basis
  }

  basis_df <- do.call(cbind, basis_list)
  model_data <- cbind(df, basis_df)
  basis_columns <- colnames(basis_df)

  basis_terms <- paste(basis_columns, collapse = " + ")
  print(basis_terms)
  formula_str <- paste(
    "Cases ~ 1 +",
    "f(ID_spat, model='iid', replicate=ID_year) +",
    "f(ID_time_cyclic, model='rw1', cyclic=TRUE, scale.model=TRUE) +",
    basis_terms
  )

  model_formula <- as.formula(formula_str)
  return(list(formula = model_formula, data = model_data))
}

# --- Main prediction function ---
predict_chap <- function(hist_fn, future_fn, preds_fn, config_path) {
  config <- parse_config(config_path)
  covariate_names <- config$additional_continuous_covariates
  nlag <- config$n_lags
  precision <- config$precision

  cat("Config: n_lags=", nlag, " precision=", precision, "\n")
  cat("Covariates:", paste(covariate_names, collapse=", "), "\n")

  historic_df <- read.csv(hist_fn)
  future_df <- read.csv(future_fn)

  # Ensure disease_cases exists in future data as NA (rows to predict)
  if (!("disease_cases" %in% colnames(future_df))) {
    future_df$disease_cases <- NA
  }

  if (nrow(historic_df) > 0) {
    df <- rbind(historic_df, future_df)
  } else {
    df <- future_df
  }

  # Apply column adapters (CHAP standard -> internal names)
  df <- apply_adapters(df)

  # Extract year and month/week from time_period if not already present
  if (!("ID_year" %in% colnames(df))) {
    df$ID_year <- as.integer(substr(df$time_period, 1, 4))
  }
  if (!("week" %in% colnames(df)) && !("month" %in% colnames(df))) {
    if (grepl("W", df$time_period[1])) {
      df$week <- as.integer(sub(".*W", "", df$time_period))
    } else {
      df$month <- as.integer(substr(df$time_period, 6, 7))
    }
  }

  if ("week" %in% colnames(df)) {
    df <- mutate(df, ID_time_cyclic = week)
    df <- offset_years_and_weeks(df)
    nlag <- 12
  } else {
    df <- mutate(df, ID_time_cyclic = month)
    df <- offset_years_and_months(df)
    nlag <- 3
  }

  df$ID_year <- df$ID_year - min(df$ID_year) + 1

  if (length(covariate_names) == 0) {
    generated <- generate_bacic_model(df, covariate_names, nlag)
  } else {
    generated <- generate_lagged_model(df, covariate_names, nlag)
  }
  lagged_formula <- generated$formula
  print(colnames(df))
  df <- generated$data
  print(colnames(df))
  model <- inla(formula = lagged_formula, data = df, family = "nbinomial", offset = log(E),
                control.inla = list(strategy = 'adaptive'),
                control.compute = list(dic = TRUE, config = TRUE, cpo = TRUE, return.marginals = FALSE),
                control.fixed = list(correlation.matrix = TRUE, prec.intercept = 1e-4, prec = precision),
                control.predictor = list(link = 1, compute = TRUE),
                verbose = F, safe=FALSE)

  casestopred <- df$Cases
  idx.pred <- which(is.na(casestopred))
  mpred <- length(idx.pred)
  s <- 1000
  y.pred <- matrix(NA, mpred, s)
  xx <- inla.posterior.sample(s, model)
  xx.s <- inla.posterior.sample.eval(function(idx.pred) c(theta[1], Predictor[idx.pred]), xx, idx.pred = idx.pred)

  for (s.idx in 1:s) {
    xx.sample <- xx.s[, s.idx]
    y.pred[, s.idx] <- rnbinom(mpred, mu = exp(xx.sample[-1]), size = xx.sample[1])
  }

  new.df <- data.frame(time_period = df$time_period[idx.pred], location = df$ID_spat[idx.pred], y.pred)
  colnames(new.df) <- c('time_period', 'location', paste0('sample_', 0:(s-1)))

  write.csv(new.df, preds_fn, row.names = FALSE)
  saveRDS(model, file = "model.rds")
  cat("Predictions written to", preds_fn, "\n")
}

# --- CLI entry point ---
args <- commandArgs(trailingOnly = TRUE)

hist_fn <- "historic.csv"
future_fn <- "future.csv"
preds_fn <- "predictions.csv"
config_path <- "config.yml"

for (i in seq_along(args)) {
  if (args[i] == "--historic" && i < length(args)) hist_fn <- args[i + 1]
  if (args[i] == "--future" && i < length(args)) future_fn <- args[i + 1]
  if (args[i] == "--output" && i < length(args)) preds_fn <- args[i + 1]
}

if (!interactive()) {
  cat("Running predictions...\n")
  cat("Historic:", hist_fn, "\n")
  cat("Future:", future_fn, "\n")
  cat("Output:", preds_fn, "\n")
  predict_chap(hist_fn, future_fn, preds_fn, config_path)
}
