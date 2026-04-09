get_last_month <- function(df) {
  df = df[!is.na(df$Cases),]
  return(df$month[length(df$month)])
}

get_last_week <- function(df) {
  df = df[!is.na(df$Cases),]
  return(df$week[length(df$week)])
}
get_week_diff <- function(df){
  last_week = get_last_week(df)

  if (last_week<=26) {
    week_diff = 26-last_week
  } else {
    week_diff = 78-last_week
  }
  return(week_diff)
}

offset_years_and_weeks <- function(df) {
  week_diff = get_week_diff(df)
  new_week = df$week + week_diff
  week = ((new_week-1) %% 52)+1
  ID_year = ifelse(new_week>52, df$ID_year+1, df$ID_year)
  df$week = week
  df$ID_year = ID_year
  return(df)
}

get_month_diff <- function(df){
  last_month = get_last_month(df)

  if (last_month<=6) {
    month_diff = 6-last_month
  } else {
    month_diff = 18-last_month
  }
  return(month_diff)
}

offset_years_and_months <- function(df) {
  month_diff = get_month_diff(df)
  new_month = df$month + month_diff
  month = ((new_month-1) %% 12)+1
  ID_year = ifelse(new_month>12, df$ID_year+1, df$ID_year)
  df$month = month
  df$ID_year = ID_year
  return(df)
}
