###############################################
# Data Gathering for Presidential Market Performance Comparison App
# This script fetches and processes market data for later use in the app
###############################################

# Load required libraries for data gathering and processing
library(dplyr)
library(lubridate)
library(quantmod)
library(tidyr)

#-------------------------------------------
# Data Setup and Helper Functions
#-------------------------------------------

# Define presidential data
# presidents_data <- data.frame(
#   president = c(
#     "Eisenhower (1957)", "Kennedy (1961)", "Johnson (1963)", "Nixon (1969)", 
#     "Nixon (1973)", "Ford (1974)", "Carter (1977)", "Reagan (1981)",
#     "Reagan (1985)", "Bush Sr. (1989)", "Clinton (1993)", "Clinton (1997)",
#     "Bush Jr. (2001)", "Bush Jr. (2005)", "Obama (2009)", "Obama (2013)",
#     "Trump (2017)", "Biden (2021)", "Trump (2025)"
#   ),
#   inauguration_date = as.Date(c(
#     "1957-01-20", "1961-01-20", "1963-11-22", "1969-01-20",
#     "1973-01-20", "1974-08-09", "1977-01-20", "1981-01-20",
#     "1985-01-20", "1989-01-20", "1993-01-20", "1997-01-20",
#     "2001-01-20", "2005-01-20", "2009-01-20", "2013-01-20",
#     "2017-01-20", "2021-01-20", "2025-01-20"
#   )),
#   election_date = as.Date(c(
#     "1956-11-06", "1960-11-08", "1960-11-08", "1968-11-05",
#     "1972-11-07", "1972-11-07", "1976-11-02", "1980-11-04",
#     "1984-11-06", "1988-11-08", "1992-11-03", "1996-11-05",
#     "2000-11-07", "2004-11-02", "2008-11-04", "2012-11-06",
#     "2016-11-08", "2020-11-03", "2024-11-05"
#   )),
#   party = c(
#     "Republican", "Democratic", "Democratic", "Republican",
#     "Republican", "Republican", "Democratic", "Republican",
#     "Republican", "Republican", "Democratic", "Democratic",
#     "Republican", "Republican", "Democratic", "Democratic",
#     "Republican", "Democratic", "Republican"
#   ),
#   stringsAsFactors = FALSE
# )
#
# write.csv(presidents_data, "presidents_data.csv", row.names = FALSE)

# Improved error handling for data loading
tryCatch({
  presidents_data <- read.csv(
    "https://raw.githubusercontent.com/jhelvy/presidential-econ-tracker/refs/heads/main/presidents_data.csv", 
    stringsAsFactors = FALSE
  )
  presidents_data$inauguration_date <- as.Date(presidents_data$inauguration_date)
  presidents_data$election_date <- as.Date(presidents_data$election_date)
}, error = function(e) {
  stop(paste("Failed to load presidents data:", e$message))
})

# Define market indices to fetch
market_indices <- data.frame(
  symbol = c("^GSPC", "^DJI", "^IXIC"),
  name = c("S&P 500", "Dow Jones", "NASDAQ"),
  id = c("sp500", "djia", "nasdaq"),
  stringsAsFactors = FALSE
)

# Define FRED economic indicators to fetch
fred_indicators <- data.frame(
  symbol = c("UNRATE", "CPIAUCSL"),
  name = c("Unemployment Rate", "Consumer Price Index"),
  id = c("unemployment", "inflation"),
  stringsAsFactors = FALSE
)

# Function to fetch market data for all indices with improved error handling and retry logic
fetch_market_data <- function(max_retries = 3, retry_delay = 5) {
  # Calculate the earliest date needed
  earliest_date <- min(presidents_data$election_date) - days(30)
  
  # Create a list to store market data
  all_data <- list()
  
  # Loop through each market index
  for (i in 1:nrow(market_indices)) {
    symbol <- market_indices$symbol[i]
    index_id <- market_indices$id[i]
    index_name <- market_indices$name[i]
    
    # Add retry logic
    for (attempt in 1:max_retries) {
      tryCatch({
        # Get symbol and ID
        message(paste("Fetching data for", index_name, "(Attempt", attempt, "of", max_retries, ")"))
        
        # Fetch data
        getSymbols(symbol, from = earliest_date, to = Sys.Date() + days(1), src = "yahoo")
        
        # Get the object based on the symbol
        obj_name <- gsub("\\^", "", symbol)
        idx_obj <- get(obj_name)
        
        # Create data frame
        idx_data <- data.frame(
          date = index(idx_obj),
          value = as.numeric(idx_obj[, paste0(obj_name, ".Adjusted")]),
          index_id = index_id,
          index_name = index_name,
          stringsAsFactors = FALSE
        )
        
        # Store in list
        all_data[[index_id]] <- idx_data
        
        # Success, break the retry loop
        break
        
      }, error = function(e) {
        warning(paste("Error fetching data for", index_name, "on attempt", attempt, ":", e$message))
        if (attempt < max_retries) {
          message(paste("Retrying in", retry_delay, "seconds..."))
          Sys.sleep(retry_delay)
        } else {
          warning(paste("Failed to fetch data for", index_name, "after", max_retries, "attempts"))
        }
      })
    }
  }
  
  # Check if we have any data
  if (length(all_data) == 0) {
    stop("Failed to fetch any market data after multiple attempts")
  }
  
  return(all_data)
}

# Function to fetch data from FRED with improved error handling and retry logic
fetch_fred_data <- function(max_retries = 3, retry_delay = 5) {
  # Calculate the earliest date needed
  earliest_date <- min(presidents_data$election_date) - days(30)
  
  # Create a list to store market data
  all_data <- list()
  
  # Loop through each FRED indicator
  for (i in 1:nrow(fred_indicators)) {
    symbol <- fred_indicators$symbol[i]
    index_id <- fred_indicators$id[i]
    index_name <- fred_indicators$name[i]
    
    # Add retry logic
    for (attempt in 1:max_retries) {
      tryCatch({
        # Fetch data
        message(paste("Fetching data for", index_name, "from FRED (Attempt", attempt, "of", max_retries, ")"))
        getSymbols(symbol, src = "FRED", from = earliest_date, to = Sys.Date() + days(1))
        
        # Get the object based on the symbol
        idx_obj <- get(symbol)
        
        # Create data frame
        idx_data <- data.frame(
          date = index(idx_obj),
          value = as.numeric(idx_obj[, 1]),
          index_id = index_id,
          index_name = index_name,
          stringsAsFactors = FALSE
        )
        
        # For CPI, convert to year-over-year percent change (inflation rate)
        if (index_id == "inflation") {
          # Calculate year-over-year percent change for CPI
          idx_data <- idx_data %>%
            arrange(date) %>%
            mutate(
              prior_year_value = lag(value, 12),
              value = ((value / prior_year_value) - 1) * 100  # YoY percent change
            ) %>%
            filter(!is.na(value)) %>%  # Remove first year where we don't have YoY comparison
            select(-prior_year_value)  # Remove the helper column
          
          # Update the index name to clarify it's YoY inflation
          idx_data$index_name <- "Inflation Rate (YoY)"
        }
        
        # Store in list
        all_data[[index_id]] <- idx_data
        
        # Success, break the retry loop
        break
        
      }, error = function(e) {
        warning(paste("Error fetching data for", index_name, "from FRED on attempt", attempt, ":", e$message))
        if (attempt < max_retries) {
          message(paste("Retrying in", retry_delay, "seconds..."))
          Sys.sleep(retry_delay)
        } else {
          warning(paste("Failed to fetch data for", index_name, "from FRED after", max_retries, "attempts"))
        }
      })
    }
  }
  
  # Check if we have any data
  if (length(all_data) == 0) {
    stop("Failed to fetch any FRED data after multiple attempts")
  }
  
  return(all_data)
}

#-------------------------------------------
# Main Data Collection Process
#-------------------------------------------

# Add overall error handling for the main process
tryCatch({
  # Fetch all market data
  message("Starting market data collection...")
  market_data <- fetch_market_data()
  
  # Fetch all FRED data
  message("Starting FRED data collection...")
  fred_data <- fetch_fred_data()
  
  # Combine all data
  message("Combining all data...")
  all_data <- c(market_data, fred_data)
  combined_data <- bind_rows(all_data)
  
  # Add metadata about when the data was retrieved
  combined_data$data_retrieved <- Sys.Date()
  
  # Merge with existing data
  existing_data <- read.csv(
      "https://raw.githubusercontent.com/jhelvy/presidential-econ-tracker/refs/heads/main/market_data.csv",
      stringsAsFactors = FALSE
  )
  
  # Convert date columns to Date objects for comparison
  existing_data$date <- as.Date(existing_data$date)
  existing_data$data_retrieved <- as.Date(existing_data$data_retrieved)
  
  # Identify new data (dates not in existing data)
  new_data <- combined_data %>%
      filter(!date %in% existing_data$date)
  
  if (nrow(new_data) > 0) {
      message(paste("Found", nrow(new_data), "new data points to add"))
      
      # Merge existing and new data
      updated_data <- bind_rows(existing_data, new_data) %>%
          arrange(index_id, date)
      
      # Save the updated data
      write.csv(updated_data, "market_data.csv", row.names = FALSE)
      message("Data collection complete. Updated market_data.csv with new data.")
  } else {
      message("No new data found. Keeping existing market_data.csv file.")
  }
    
}, error = function(e) {
  stop(paste("Error in data collection process:", e$message))
})
