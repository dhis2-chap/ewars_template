# left side is the names used in the code, right side is the internal names in CHAP
# Cases = number of cases
# E = population
# week = week
# month = month
# ID_year = year
# ID_spat = location
# rainsum = rainfall
# meantemperature = mean_temperature
#note: The model uses either weeks or months
#install.packages('yaml')
library(yaml)
library(jsonlite)
# install.packages('dplyr')
library(INLA)
library(dlnm)
library(dplyr)
source("lib.R")

#for spatial effects
library(sf)
library(spdep)

parse_model_configuration <- function(file_path) {
  # Load YAML content
  config <- yaml.load_file(file_path)
  print(config)
  
  # Ensure fields exist and provide defaults if missing
  user_option_values <- if (!is.null(config$user_option_values)) {
    fromJSON(toJSON(config$user_option_values))
  } else {
    list()
  }
  
  additional_continuous_covariates <- if (!is.null(config$additional_continuous_covariates)) {
    config$additional_continuous_covariates
  } else {
    character()
  }
  
  # Return the structured list
  list(
    user_option_values = user_option_values,
    additional_continuous_covariates = additional_continuous_covariates
  )
}

generate_bacic_model <- function(df, covariates, nlag, region_seasonal) {
  formula_str <- paste(
    "Cases ~ 1 +",
    "f(ID_spat, model='iid', replicate=ID_year) +",
    "f(ID_time_cyclic, model='rw1', cyclic=TRUE, scale.model=TRUE)"
  )
  if(region_seasonal){
    formula_str <- paste(formula_str, "+ f(ID_time_cyclic2, model='rw1',
                         cyclic=TRUE, scale.model=TRUE, replicate=ID_spat)")
  }
  
  model_formula <- as.formula(formula_str)
  
  return(list(formula = model_formula, data = df))
}

generate_lagged_model <- function(df, covariates, nlag, region_seasonal) {
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
  
  # Combine basis matrices into one data frame
  basis_df <- do.call(cbind, basis_list)
  
  # Merge with the original dataframe
  model_data <- cbind(df, basis_df)
  
  # Get all new column names added
  basis_columns <- colnames(basis_df)
  
  # Generate formula string using column names directly
  basis_terms <- paste(basis_columns, collapse = " + ")
  print(basis_terms)
  formula_str <- paste(
    "Cases ~ 1 +",
    "f(ID_spat, model='iid', replicate=ID_year) +",
    "f(ID_time_cyclic, model='rw1', cyclic=TRUE, scale.model=TRUE) +",
    basis_terms
  )
  
  if(region_seasonal){
    formula_str <- paste(formula_str, "+ f(ID_time_cyclic2, model='rw1',
                         cyclic=TRUE, scale.model=TRUE, replicate=ID_spat)")
  }
  
  model_formula <- as.formula(formula_str)
  
  return(list(formula = model_formula, data = model_data))
}

predict_chap <- function(model_fn, hist_fn, future_fn, preds_fn, config_fn=""){
  #load(file = model_fn) #would normally load a model here
  if (config_fn != "") {
    print("Loading model configuration from YAML file...")
    print(config_fn)
    config <- parse_model_configuration(config_fn)
    covariate_names <- config$additional_continuous_covariates
    nlag<- config$user_option_values$n_lag
    if(is.null(nlag)){nlag <- 3}
    precision <- config$user_option_values$precision
    if(is.null(precision)){precision <- 0.01}
    region_seasonal <- config$user_option_values$region_seasonal
    if(is.null(region_seasonal)){region_seasonal <- FALSE}
    # Use config$user_option_values and config$additional_continuous_covariates as needed
  } else {
    covariate_names <- c("rainfall", "mean_temperature")
    precision <- 0.01
    region_seasonal <- 1
  }
  print(precision)
  print(nlag)
  print(region_seasonal)
  df <- read.csv(future_fn) #the two columns on the next lines are not normally included in the future df
  df$Cases <- rep(NA, nrow(df))
  df$disease_cases <- rep(NA, nrow(df)) #so we can rowbind it with historic
  
  historic_df = read.csv(hist_fn)
  df <- rbind(historic_df, df) 
  
  if( "week" %in% colnames(df)){ # for a weekly model
    df <- mutate(df, ID_time_cyclic = week)
    df <- offset_years_and_weeks(df)
  } else{ # for a monthly model
    df <- mutate(df, ID_time_cyclic = month)
    df <- offset_years_and_months(df)
  }
  
  #for region_seasonal
  df$ID_time_cyclic2 <- df$ID_time_cyclic
  
  df$ID_year <- df$ID_year - min(df$ID_year) + 1 #makes the years 1, 2, ...
  
  if (length(covariate_names) == 0) {
    generated <- generate_bacic_model(df, covariate_names, nlag, region_seasonal)
  } else {
    generated <- generate_lagged_model(df, covariate_names, nlag, region_seasonal)
  }
  lagged_formula <- generated$formula
  print(colnames(df))
  df <- generated$data
  print(colnames(df))
  df$ID_spat <- as.integer(as.factor(df$ID_spat)) #to avoid issues with replicate
  
  model <- inla(formula = lagged_formula, data = df, family = "nbinomial", offset = log(E),
                control.inla = list(strategy = 'adaptive'),
                control.compute = list(dic = TRUE, config = TRUE, cpo = TRUE, return.marginals = FALSE),
                control.fixed = list(correlation.matrix = TRUE, prec.intercept = 1e-4, prec = precision),
                control.predictor = list(link = 1, compute = TRUE),
                verbose = F, safe=FALSE)
  
  casestopred <- df$Cases # response variable
  
  # Predict only for the cases where the response variable is missing
  idx.pred <- which(is.na(casestopred)) #this then also predicts for historic values that are NA, not ideal
  mpred <- length(idx.pred)
  s <- 1000
  y.pred <- matrix(NA, mpred, s)
  # Sample parameters of the model
  xx <- inla.posterior.sample(s, model)  # This samples parameters of the model
  xx.s <- inla.posterior.sample.eval(function(idx.pred) c(theta[1], Predictor[idx.pred]), xx, idx.pred = idx.pred) # This extracts the expected value and hyperparameters from the samples
  
  # Sample predictions
  for (s.idx in 1:s){
    xx.sample <- xx.s[, s.idx]
    y.pred[, s.idx] <- rnbinom(mpred,  mu = exp(xx.sample[-1]), size = xx.sample[1])
  }
  
  # make a dataframe where first column is the time points, second column is the location, rest is the samples
  # rest of columns should be called sample_0, sample_1, etc
  new.df = data.frame(time_period = df$time_period[idx.pred], location = df$location[idx.pred], y.pred)
  colnames(new.df) = c('time_period', 'location', paste0('sample_', 0:(s-1)))
  
  # Write new dataframe to file, and save the model?
  write.csv(new.df, preds_fn, row.names = FALSE)
  saveRDS(model, file = model_fn)
}

args <- commandArgs(trailingOnly = TRUE)

if (length(args) >= 1) {
  cat("running predictions")
  print(args)
  model_fn <- args[1]
  hist_fn <- args[2]
  future_fn <- args[3]
  preds_fn <- args[4]
  if (length(args) == 5) {
    config_fn <- args[5]
  } else {
    config_fn <- ""
  }
  predict_chap(model_fn, hist_fn, future_fn, preds_fn, config_fn)
}

#Testing

# model_fn <- "example_data_monthly/model"
# hist_fn <- "example_data_monthly/historic_data.csv"
# future_fn <- "example_data_monthly/future_data.csv"
# preds_fn <- "example_data_monthly/predictions.csv"
# config_fn <- "model_configuration_for_run.yaml"

