library(yaml)

# Training is a no-op for this model — all fitting happens during prediction.
# This script validates the inputs and saves a placeholder model file.

args <- commandArgs(trailingOnly = TRUE)

# Parse --data argument
data_file <- NULL
for (i in seq_along(args)) {
  if (args[i] == "--data" && i < length(args)) {
    data_file <- args[i + 1]
  }
}

if (is.null(data_file)) {
  data_file <- "data.csv"
}

# Read config from workspace
config <- if (file.exists("config.yml")) {
  yaml.load_file("config.yml")
} else {
  list()
}

# Read and validate training data
cat("Reading training data from:", data_file, "\n")
df <- read.csv(data_file)
cat("Training data shape:", nrow(df), "rows x", ncol(df), "columns\n")
cat("Columns:", paste(colnames(df), collapse=", "), "\n")

# Save placeholder model (actual fitting happens in predict step)
saveRDS(list(trained = TRUE, n_rows = nrow(df)), file = "model.rds")
cat("Model placeholder saved to model.rds\n")
