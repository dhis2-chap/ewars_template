# Bug: `chapkit test` generates unusable prediction data

## Summary

`chapkit test` generates prediction test data with an **empty historic dataset** and **disease_cases values in future data**, making it impossible for models that follow the standard train/predict pattern (historic data with observations + future data with NA target values).

## Version

chapkit 0.16.7

## Location

`chapkit/cli/test/generator.py` — `TestDataGenerator.generate_prediction_data()` (line ~84)

## Problem

The `generate_prediction_data()` method:

1. **Returns empty historic data** (hardcoded `{"columns": columns, "data": []}`):
   ```python
   historic: dict[str, Any] = {"columns": columns, "data": []}
   ```

2. **Returns future data with actual disease_cases values** (generated via `generate_training_data()` which fills in random integer values for the target):
   ```python
   future = self.generate_training_data(...)
   ```

3. **`prediction_periods` defaults to 0** in generated configs because `_generate_value_for_schema()` returns `variation` (which is `0` for the first config) for integer fields without a default value.

### Result

- `prediction_0_0_historic.csv`: headers only, zero data rows
- `prediction_0_0_future.csv`: all rows have populated `disease_cases`
- `config_0.json`: `prediction_periods: 0`

Any model that expects non-empty historic data or uses NA/missing `disease_cases` in future data to identify rows to predict will fail.

## Expected behavior

- **historic.csv**: contains rows with actual `disease_cases` values (the observations)
- **future.csv**: contains rows with `disease_cases` set to `null`/NA (the rows the model should predict)
- **config**: `prediction_periods` >= 1

## Suggested fix

### `generator.py` — `generate_prediction_data()`

Generate a full dataset, then split it into historic (earlier periods with values) and future (later periods with NA disease_cases):

```python
def generate_prediction_data(self, num_locations=5, num_periods=12, ...,
                             prediction_periods=3):
    total_periods = max(num_periods, prediction_periods + 1)

    full_data = self.generate_training_data(
        num_locations=num_locations,
        num_periods=total_periods, ...
    )

    columns = full_data["columns"]
    all_rows = full_data["data"]
    all_periods = sorted(set(row[0] for row in all_rows))
    split_point = len(all_periods) - prediction_periods
    historic_periods = set(all_periods[:split_point])
    future_periods = set(all_periods[split_point:])

    disease_cases_idx = columns.index("disease_cases")

    historic_rows = [row for row in all_rows if row[0] in historic_periods]
    future_rows = []
    for row in all_rows:
        if row[0] in future_periods:
            row_copy = list(row)
            row_copy[disease_cases_idx] = None
            future_rows.append(row_copy)

    return (
        {"columns": columns, "data": historic_rows},
        {"columns": columns, "data": future_rows},
    )
```

### `generator.py` — `generate_config_data_from_schema()`

Ensure `prediction_periods` is at least 1:

```python
# After generating all fields:
if "prediction_periods" in data and isinstance(data["prediction_periods"], int):
    data["prediction_periods"] = max(1, data["prediction_periods"])
```
