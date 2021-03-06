rm(list  = ls())
library(TSstudio)
library(tsibble)


data("USgas")


input <- as_tsibble(USgas)
input
input %>% index_valid()

tsibble::is_regular(input)

# Frequency option
# Quarterly series -> quarter
# Monthly series -> month, quarter
# Weekly series -> week, month, and quarter
# Daily series -> day of the year, day of the week, week, month, and quarter
# Hourly series -> hour, day of the week, day of the year, day of the week, week, month, and quarter


input <- USgas

ts_reg <- function(input,
                   y = NULL,
                   x = NULL,
                   seasonal = NULL,
                   trend = list(linear = TRUE, exponential = FALSE, log = FALSE, power = FALSE),
                   lags = NULL,
                   method =  "lm",
                   method_arg = list(step = FALSE, direction = "both"),
                   scale = NULL){
  
  `%>%` <- magrittr::`%>%`
  
  freq <- md <- time_stamp <- new_features <- NULL
  
  # Error handling
  
  # Check the trend argument
    
    if(!base::is.list(trend) || !all(base::names(trend) %in% c("linear", "exponential", "log", "power"))){
    stop("The 'trend' argument is not valid")
    } else{
      
      if(!"linear" %in% base::names(trend)){
        trend$linear <- FALSE      
      } else if(!base::is.logical(trend$linear)){
        stop("The 'linear' argument of the trend must be either TRUE or FALSE")
      }
      
      
      if(!"exponential" %in% base::names(trend)){
        trend$exponential <- FALSE      
      } else if(!base::is.logical(trend$exponential)){
        stop("The 'exponential' argument of the trend must be either TRUE or FALSE")
      }
      
      if(!"log" %in% base::names(trend)){
        trend$log <- FALSE      
      } else if(!base::is.logical(trend$log)){
        stop("The 'log' argument of the trend must be either TRUE or FALSE")
      }
      
      if(!"power" %in%  base::names(trend)){
        trend$power <- FALSE
      } else if(!base::is.numeric(trend$power) && trend$power != FALSE){
        stop("The value of the 'power' argument is not valid, can be either a numeric ",
             "(e.g., 2 for square, 0.5 for square root, etc.), or FALSE for disable")
      }
      
     if(trend$linear && trend$power == 1){
       warning("Setting both the 'power' argument to 1 and the 'linear' argument to TRUE is equivalent. ",
       "To avoid redundancy in the variables, setting 'linear' to FALSE")
     }
    }
    
  
  
  # Check if the x variables are in the input obj
  if(!base::is.null(x)){
    if(!base::all(x %in% names(input))){
      stop("Some or all of the variables names in the 'x' argument do not align with the column names of the input object")
    }
  }
  
  
  # Checking the lags argument
  if(!base::is.null(lags)){
    if(!base::is.numeric(lags) || base::any(lags %% 1 != 0 ) || base::any(lags <= 0)){
      stop("The value of the 'ar' argument is not valid. Must be a positive integer")
    }
  }
  
  # Checking the scale argument
  if(!is.null(scale)){
    if(base::length(scale) > 1 || !base::any(c("log", "normal", "standard") %in% scale)){
      stop("The value of the 'scale' argument are not valid")
    }
  }
  
  # Setting the input table
  if(base::any(base::class(input) == "tbl_ts")){
    df <- input
  } else if(any(class(input) == "ts")){
    df <- tsibble::as_tsibble(input) %>% setNames(c("index", "y"))
    y <- "y"
    if(!base::is.null(x)){
      warning("The 'x' argument cannot be used when input is a 'ts' class")
    }
    x <- NULL
  }
  
  time_stamp <- base::attributes(df)$index2
  
  freq <- base::list(unit = base::names(base::which(purrr::map(tsibble::interval(df), ~.x) > 0)),
                     value = tsibble::interval(df)[which(tsibble::interval(df) != 0)] %>% base::as.numeric(),
                     frequency = stats::frequency(df))
  
  
  # Scaling the series
  if(!base::is.null(scale)){
    if(scale == "log"){
      df$y_log <- base::log(df$y)
      y <- "y_log"
    } else if(scale == "normal"){
      df$y_normal <- (df$y - base::min(df$y)) / (base::max(df$y) - base::min(df$y))
      y <- "y_normal"
    } else if(scale == "standard"){
      df$y_standard <- (df$y - base::mean(df$y)) / stats::sd(df$y)
      y <- "y_standard"
    }
  }
  
  
  
  # Setting the frequency component
  if(!base::is.null(seasonal)){
    
    # Case series frequency is quarterly
    
    if(freq$unit == "quarter"){
      if(base::length(seasonal) == 1 & seasonal == "quarter"){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "quarter")
      } else if(base::length(seasonal) > 1 & "quarter" %in% seasonal){
        warning("Only quarter seasonal component can be used with quarterly frequency")
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "quarter")
      } else {
        stop("The seasonal component is not valid")
      }
      
      # Case series frequency is monthly
      
    } else if(freq$unit == "month"){
      if(base::length(seasonal) == 1 && seasonal == "month"){
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "month")
      } else if(all(seasonal %in% c("month", "quarter"))){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "month", "quarter")
      } else if(any(seasonal %in% c("month", "quarter"))){
        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }
        
        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }
        
        warning("For monthly frequency only 'month' or 'quarter' seasonal component could be used with the 'seasonal' argument")
      } else {stop("The seasonal component is not valid")}
      
      # Case series frequency is weekly
      
    } else if(freq$unit == "week"){
      if(base::length(seasonal) == 1 && seasonal == "week"){
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "week")
      } else if(all(c("week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "week","month", "quarter")
      } else if(any(c("week", "month", "quarter") %in% seasonal)){
        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }
        
        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }
        
        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }
        
        warning("For weekly frequency only 'week', 'month', or 'quarter' seasonal component could be used with the 'seasonal' argument")
      } else {stop("The seasonal component is not valid")}
      
      # Case series frequency is daily
      
    } else if(freq$unit == "day"){
      if(base::length(seasonal) == 1 && seasonal == "wday"){
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "wday")
      } else if(base::length(seasonal) == 1 && seasonal == "yday"){
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "yday")
      } else if(all(c("wday", "yday","week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "wday", "yday", "week","month", "quarter")
      } else if(any(c("wday", "yday","week", "month", "quarter") %in% seasonal)){
        if("wday" %in% seasonal){
          df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "wday")
        }
        
        if("yday" %in% seasonal){
          df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "yday")
        }
        
        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }
        
        
        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }
        
        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }
        
        warning("For daily frequency only 'wday', 'yday', 'week', 'month', or 'quarter' seasonal component could be used with the 'seasonal' argument")
      } else {stop("The seasonal component is not valid")}
      
      # Case series frequency is hourly
      
    } else if(freq$unit == "hour"){
      if(base::length(seasonal) == 1 && seasonal == "hour"){
        df$hour <- lubridate::hour(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "hour")
      } else if(all(c("hour", "wday", "yday","week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "hour","wday", "yday", "week","month", "quarter")
      } else if(any(c("hour","wday", "yday","week", "month", "quarter") %in% seasonal)){
        if("hour" %in% seasonal){
          df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "hour")
        }
        
        if("wday" %in% seasonal){
          df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "wday")
        }
        
        if("yday" %in% seasonal){
          df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "yday")
        }
        
        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }
        
        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }
        
        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }
        
        warning("For daily frequency only 'hour', 'wday', 'yday', 'week', 'month', or 'quarter' seasonal component could be used with the 'seasonal' argument")
      } else {stop("The seasonal component is not valid")}
    } else if(freq$unit == "minute"){
      if(base::length(seasonal) == 1 && seasonal == "minute"){
        df$minute <- (lubridate::hour(df[[time_stamp]]) * 2 + (lubridate::minute(df[[time_stamp]]) + freq$value )/ freq$value )%>%
          factor(ordered = FALSE)
        new_features <- c(new_features, "minute")
      } else if(all(c("minute", "hour", "wday", "yday","week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
        df$minute <- (lubridate::hour(df[[time_stamp]]) * 2 + (lubridate::minute(df[[time_stamp]]) + freq$value )/ freq$value) %>%
          base::factor(ordered = FALSE)
        new_features <- c(new_features, "minute", "hour","wday", "yday", "week","month", "quarter")
      } else if(any(c("minute", "hour","wday", "yday","week", "month", "quarter") %in% seasonal)){
        if("minute" %in% seasonal){
          df$minute <- (lubridate::hour(df[[time_stamp]]) * 2 + (lubridate::minute(df[[time_stamp]]) + freq$value )/ freq$value) %>%
            base::factor(ordered = FALSE)
          new_features <- c(new_features, "minute")
        }
        
        if("hour" %in% seasonal){
          df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "hour")
        }
        
        if("wday" %in% seasonal){
          df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "wday")
        }
        
        if("yday" %in% seasonal){
          df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "yday")
        }
        
        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }
        
        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }
        
        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }
        
        warning("For daily frequency only 'hour', 'wday', 'yday', 'week', 'month', or 'quarter' seasonal component could be used with the 'seasonal' argument")
      } else {stop("The seasonal component is not valid")}
    }
  }
  
  
  # Setting the trend
  if(base::is.numeric(trend$power)){
    for(i in trend$power){
      df[[base::paste("trend_power_", i, sep = "")]] <- c(1:base::nrow(df)) ^ i
      new_features <- c(new_features, base::paste("trend_power_", i, sep = ""))
    }
  }
  
  if(trend$exponential){
    df$exp_trend <- base::exp(1:base::nrow(df))
    new_features <- c(new_features, "exp_trend")
  }
  
  if(trend$log){
    df$log_trend <- base::log(1:base::nrow(df))
    new_features <- c(new_features, "log_trend")
  }
  
  if(trend$linear){
    df$linear_trend <- 1:base::nrow(df)
    new_features <- c(new_features, "linear_trend")
  }
  
  
  
  # Setting the lags variables
  
  if(!base::is.null(lags)){
    for(i in lags){
      df[base::paste("lag_", i, sep = "")] <- df[[y]] %>% dplyr::lag( i)
      new_features <- c(new_features, base::paste("lag_", i, sep = ""))
    }
    df1 <- df[(max(lags)+ 1):base::nrow(df),]
  } else {
    df1 <- df
  }
  
  
  if(method == "lm"){
    if(!base::is.null(x)){
      f <- stats::as.formula(paste(y, "~ ", paste0(x, collapse = " + "), "+", paste0(new_features, collapse = " + ")))
    } else{
      f <- stats::as.formula(paste(y, "~ ", paste0(new_features, collapse = " + ")))
    }
    if(method_arg$step){
      md_init <- NULL
      md_init <- stats::lm(f, data = df1)
      md <- step(md_init, direction = method_arg$direction)
    } else(
      md <- stats::lm(f, data = df1)
    )
    
  }
  
  
  output <- list(model = md,
                 parameters = list(y = y,
                                   x = x,
                                   new_features = new_features,
                                   seasonal = seasonal,
                                   trend = trend,
                                   lags = lags,
                                   method = method,
                                   method_arg = method_arg,
                                   scale = scale,
                                   frequency = freq),
                 series = df)
  
  final_output <- base::structure(output, class = "forecastML")
  
  return(final_output)
  
}
  
  

x1 <- ts_reg (input = AirPassengers, 
        y = NULL, 
        x = NULL, 
        seasonal = "month",
        trend = list(power = FALSE,linear = TRUE),
        lags = c(1, 3, 12), 
        method =  "lm", 
        method_arg = list(step = T, direction = "both"),
        scale = "log")

summary(x1$model)
model <- x1
x1$parameters


library(tsibbledata)

data("ansett")
head(ansett)
str(ansett)
df <- UKgrid::extract_grid(type = "tbl")

data("vic_elec")
head(vic_elec)
str(vic_elec)

data(global_economy)
data(aus_production)
data(ansett)
head(df)
df1 <- tsibble::as_tsibble(df, index = TIMESTAMP)
df1

TSstudio::ts_plot(vic_elec[, c("Time", "Demand", "Temperature")])


x1 <- ts_reg(input = vic_elec,
             y = "Demand",
             x = "Temperature",
             seasonal = c("hour", "wday", "month"),
             trend = list(power = c(1), exponential = F, log = T),
             lags = 48,
             method =  "lm",
             method_arg = list(step = T, direction = "both"),
             scale = NULL)
summary(x1$model)

x1 <- ts_reg(input = aus_production,
             y = "Beer",
             x = NULL,
             seasonal = c("quarter"),
             trend = list(power = c(1), exponential = F, log = T),
             lags = 4,
             method =  "lm",
             method_arg = list(step = T, direction = "both"),
             scale = NULL)
summary(x1$model)

x1 <- ts_reg(input = ansett,
             y = "Passengers",
             x = NULL,
             seasonal = c("week"),
             trend = list(power = c(1), exponential = F, log = T),
             lags = 1,
             method =  "lm",
             method_arg = list(step = T, direction = "both"),
             scale = NULL)

summary(x1$model)



x1 <- ts_reg(input = df1,
             y = "ND",
             x = NULL,
             seasonal = c("wday", "month"),
             trend = list(power = c(0.5), exponential = F, log = T, linear = T),
             lags = c(1:24),
             method =  "lm",
             method_arg = list(step = F, direction = "both"),
             scale = NULL)

summary(x1$model)

x1 <- ts_reg(input = na.omit(global_economy %>% dplyr::filter(Country == "United States")),
             y = "GDP",
             x = NULL,
             # seasonal = c("hour", "wday", "month"),
             trend = list(power = c(1), exponential = F, log = T),
             lags = 1,
             method =  "lm",
             method_arg = list(step = T, direction = "both"),
             scale = NULL)
summary(x1$model)
model <- x1





predictML <- function(model, newdata = NULL, h){
  
  forecast_df <- NULL
  # Error handling
  if(class(model) != "forecastML"){
    stop("The input model is invalid, must be a 'forecastML' object")
  }
  
  if(base::is.null(h)){
    stop("The forecast horizon argument, 'h', is missing")
  } else if(!base::is.numeric(h)){
    stop("The forecast horizon argument, 'h', must be integer")
  } else if(h %% 1 != 0){
    stop("The forecast horizon argument, 'h', must be integer")
  }
 
  if(!base::is.null(model$parameters$x) && base::is.null(newdata)){
    stop("The input model was trained with regressors, the 'newdata' argument must align to the 'x' argument of the trained model")
  } else if(!base::is.null(model$parameters$x) && !base::all(model$parameters$x %in% base::names(newdata))){
    stop("The columns names of the 'newdata' input is not aligned with the variables names that was used on the training process")
  }
  
  if(!base::is.null(newdata)){
  if(base::nrow(newdata) != h){
    warning("The length of the input data ('newdata') is not aligned with the forecast horizon ('h'). Setting the forecast horizon as the number of rows of the input data.")
    h <- base::nrow(newdata)
  }
  }
  
  # Creating new features for the forecast data frame
  if(model$parameters$frequency$unit == "year"){
    start_date <- base::max(model$series[[base::attributes(model$series)$index2]]) + model$parameters$frequency$value
    forecast_df <- base::data.frame(index = base::seq(from = start_date, 
                          by = model$parameters$frequency$value,
                          length.out = h))
  } else if(model$parameters$frequency$unit == "quarter"){
    start_date <- base::max(model$series[[base::attributes(model$series)$index2]]) + lubridate::quarter(model$parameters$frequency$value)
    forecast_df <- base::data.frame(index = base::seq(from = start_date, 
                          by = model$parameters$frequency$value,
                          length.out = h))
  } else if(model$parameters$frequency$unit == "month"){
    start_date <- base::max(model$series[[base::attributes(model$series)$index2]]) + lubridate::month(model$parameters$frequency$value)
    forecast_df <- base::data.frame(index = base::seq(from = start_date, 
                                                      by = model$parameters$frequency$value,
                                                      length.out = h))
  } else if(model$parameters$frequency$unit == "week"){
    start_date <- base::max(model$series[[base::attributes(model$series)$index2]]) + model$parameters$frequency$value
    forecast_df <- base::data.frame(index = base::seq(from = start_date, 
                                                      by = model$parameters$frequency$value,
                                                      length.out = h))
  } else if(model$parameters$frequency$unit == "day"){
    start_date <- base::max(model$series[[base::attributes(model$series)$index2]]) + lubridate::days(model$parameters$frequency$value)
    forecast_df <- base::data.frame(index = base::seq(from = start_date, 
                                                      by = model$parameters$frequency$value,
                                                      length.out = h))
  } else if(model$parameters$frequency$unit == "hour"){
    start_date <- base::max(model$series[[base::attributes(model$series)$index2]]) + lubridate::hours(model$parameters$frequency$value)
    forecast_df <- base::data.frame(index = base::seq.POSIXt(from = start_date, 
                                                      by = model$parameters$frequency$unit,
                                                      length.out = h))
  } else if(model$parameters$frequency$unit == "minute"){
    start_date <- base::max(model$series[[base::attributes(model$series)$index2]]) + lubridate::minutes(model$parameters$frequency$value)
    forecast_df <- base::data.frame(index = base::seq.POSIXt(from = start_date, 
                                                             by = base::paste(model$parameters$frequency$value ,"min"),
                                                             length.out = h))
  }
  
  
  
  # Setting the seasonal arguments
  seasonal <- model$parameters$seasonal
  
  if(!base::is.null(seasonal)){
    if("minute" %in% seasonal){
      forecast_df$minute <- (lubridate::hour(forecast_df[["index"]]) * 2 + (lubridate::minute(forecast_df[["index"]]) + freq$value )/ freq$value) %>%
        base::factor(ordered = FALSE)
    }
    
    if("hour" %in% seasonal){
      forecast_df$hour <- (lubridate::hour(forecast_df[["index"]]) + 1) %>% base::factor(ordered = FALSE)
    }
    
    if("wday" %in% seasonal){
      forecast_df$wday <- lubridate::wday(forecast_df[["index"]], label = TRUE) %>% base::factor(ordered = FALSE)
    }
    
    if("yday" %in% seasonal){
      forecast_df$yday <- lubridate::yday(forecast_df[["index"]]) %>% base::factor(ordered = FALSE)
    }
    
    if("week" %in% seasonal){
      forecast_df$week <- lubridate::week(forecast_df[["index"]]) %>% base::factor(ordered = FALSE)
    }
    
    if("month" %in% seasonal){
      forecast_df$month <- lubridate::month(forecast_df[["index"]], label = TRUE) %>% base::factor(ordered = FALSE)
    }
    
    if("quarter" %in% seasonal){
      forecast_df$quarter <- lubridate::quarter(forecast_df[["index"]]) %>% base::factor(ordered = FALSE)
    }
    
  }
  # Setting the trend arguments
  trend <- trend_start <- trend_end <- NULL
  trend <- model$parameters$trend
  trend_start <- base::nrow(model$series) + 1
  trend_end <- trend_start + base::nrow(forecast_df) - 1
  
  if(base::is.numeric(trend$power)){
    for(i in trend$power){
      forecast_df[[base::paste("trend_power_", i, sep = "")]] <- c(trend_start:trend_end) ^ i
    }
  }
  
  if(trend$exponential){
    forecast_df$exp_trend <- base::exp(trend_start:trend_end)
  }
  
  if(trend$log){
    forecast_df$log_trend <- base::log(trend_start:trend_end)
  }
  
  if(trend$linear){
    forecast_df$linear_trend <- trend_start:trend_end
  }
  
  if(!base::is.null(model$parameters$lags)){
    for(i in model$parameters$lags){
      forecast_df[[base::paste("lag_", i, sep = "")]] <- c(model$series[[model$parameters$y]][(base::nrow(model$series) - i + 1):base::nrow(model$series)] , base::rep(NA,base::nrow(forecast_df) - i))
    }
  }
  
  
  if(model$parameters$method == "lm"){
  forecast_df$yhat <- NA
 
  if(!base::is.null(model$parameters$lags)){
    for(i in 1:base::nrow(forecast_df)){
      forecast_df$yhat[i] <- stats::predict(model$model, newdata = forecast_df[i,])
      for(l in model$parameters$lags){
        if(i + l <= base::nrow(forecast_df)){
          forecast_df[[base::paste("lag_", l, sep = "")]][i + l] <- forecast_df$yhat[i] 
        }
      }
    }
  } else {
    forecast_df$yhat <- stats::predict(model$model, newdata = forecast_df)
  }
  }
  
 return(forecast_df) 
  
}


tsibble::interval(df)[which(names(tsibble::interval(df)) == attributes(df)$interval)] %>% base::as.numeric()


x <- tsibble::interval(df)
tsibble::interval(df)[which(tsibble::interval(df) != 0)]

