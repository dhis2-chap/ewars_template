
source("train.R")
source("predict.R")

#test for weekly data, fails with nlag = 12 since the dataset is too small
train_chap("example_data/trainData.csv", "example_data/model")
predict_chap("example_data/model", "example_data/training_data.csv", "example_data/future_data.csv", "example_data/predictions.csv")

#test for monthly data
train_chap("example_data_monthly/trainData.csv", "example_data_monthly/model")
predict_chap("example_data_monthly/model", "example_data_monthly/historic_data.csv", "example_data_monthly/future_data.csv", "example_data_monthly/predictions.csv", "example_config.yaml")

# library(tsibble)
# library(dplyr)
# preds <- read.csv("example_data/predictions.csv")
# model <- readRDS("example_data/model")
# 
# summary(model)
# 
# preds <- filter(preds, yearmonth(time_period) >= yearmonth("2017-01")) #only works for this specific test data
# yearmonth(preds[1, "time_period"]) < yearmonth("2017-01")

