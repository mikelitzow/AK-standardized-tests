# Download economic (and adult education) indicators for Alaska school
# districts from the Census Bureau, without an API key:
#
# - ACS 2020-2024 5-year table-based summary files (school district geography):
#     B19013 median household income, B19301 per capita income,
#     B15003 educational attainment of adults 25+
# - SAIPE school district estimates, income years 2022-2024: total population,
#     children 5-17, and children 5-17 in families in poverty
#
# Census geographies use the NCES district ID (LEAID = "02" + 5 digits).
# Sources:
#   https://www2.census.gov/programs-surveys/acs/summary_file/2024/table-based-SF/
#   https://www.census.gov/programs-surveys/saipe/data/datasets.html
# Run from the project root.

library(tidyverse)

options(timeout = 600)
acs_base <- "https://www2.census.gov/programs-surveys/acs/summary_file/2024/table-based-SF/data/5YRData"
acs_tables <- c("b19013", "b19301", "b15003")
raw_dir <- "data/raw/census"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

# ACS: keep the US, Alaska and Alaska unified school district rows ------------

acs_ak_rows <- function(table) {
  out <- file.path(raw_dir, sprintf("acsdt5y2024-%s_ak.dat", table))
  if (!file.exists(out)) {
    tmp <- tempfile(fileext = ".dat")
    download.file(file.path(acs_base, sprintf("acsdt5y2024-%s.dat", table)), tmp, mode = "wb", quiet = TRUE)
    lines <- read_lines(tmp)
    keep <- c(lines[1], lines[str_detect(lines, "^(0100000US|0400000US02)\\||^9700000US02")])
    write_lines(keep, out)
    unlink(tmp)
  }
  read_delim(out, delim = "|", col_types = cols(GEO_ID = "c", .default = "d"))
}

acs <- map(acs_tables, acs_ak_rows) |>
  reduce(full_join, by = "GEO_ID")

# ACS special values: estimate 250001 = top-coded "$250,000+";
# negative MOE codes (e.g. -333333333) = MOE not applicable
acs_clean <- acs |>
  transmute(
    geo_id = GEO_ID,
    geo_level = case_when(
      str_starts(geo_id, "01") ~ "US",
      str_starts(geo_id, "04") ~ "State",
      TRUE ~ "District"
    ),
    leaid = if_else(geo_level == "District", str_sub(geo_id, -7), NA_character_),
    med_hh_income = if_else(B19013_E001 < 0, NA_real_, B19013_E001),
    med_hh_income_moe = if_else(B19013_M001 < 0, NA_real_, B19013_M001),
    med_hh_income_topcoded = B19013_E001 >= 250001,
    per_capita_income = if_else(B19301_E001 < 0, NA_real_, B19301_E001),
    per_capita_income_moe = if_else(B19301_M001 < 0, NA_real_, B19301_M001),
    adults_25plus = B15003_E001,
    # high school diploma/GED or more = lines 017-025; bachelor's or more = 022-025
    hs_plus_n = B15003_E017 + B15003_E018 + B15003_E019 + B15003_E020 +
      B15003_E021 + B15003_E022 + B15003_E023 + B15003_E024 + B15003_E025,
    ba_plus_n = B15003_E022 + B15003_E023 + B15003_E024 + B15003_E025,
    ba_plus_n_moe = sqrt(B15003_M022^2 + B15003_M023^2 + B15003_M024^2 + B15003_M025^2),
    pct_hs_plus = 100 * hs_plus_n / adults_25plus,
    pct_ba_plus = 100 * ba_plus_n / adults_25plus,
    # ACS approximation for the MOE of a proportion
    pct_ba_plus_moe = 100 * sqrt(pmax(ba_plus_n_moe^2 - (ba_plus_n / adults_25plus)^2 * B15003_M001^2, 0)) / adults_25plus
  )

# SAIPE ------------------------------------------------------------------------

saipe_years <- 2022:2024

read_saipe <- function(y) {
  yy <- y %% 100
  out <- file.path(raw_dir, sprintf("sd%02d-ak.txt", yy))
  if (!file.exists(out)) {
    url <- sprintf("https://www2.census.gov/programs-surveys/saipe/datasets/%d/%d-school-districts/sd%02d-ak.txt", y, y, yy)
    download.file(url, out, mode = "wb", quiet = TRUE)
  }
  # fixed-width rows: state FIPS, district ID, name, total population,
  # children 5-17, children 5-17 in poverty, file name, file date
  read_lines(out) |>
    str_match("^(\\d{2}) (\\d{5}) (.+?)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\S+)\\s+(\\S+)\\s*$") |>
    as_tibble(.name_repair = "minimal") |>
    set_names(c("line", "fips", "lea", "name", "pop_total", "pop_5_17", "pov_5_17", "file", "file_date")) |>
    transmute(
      saipe_year = y, leaid = paste0(fips, lea), census_name = name,
      pop_total = as.numeric(pop_total), pop_5_17 = as.numeric(pop_5_17),
      pov_5_17 = as.numeric(pov_5_17),
      child_poverty_pct = 100 * pov_5_17 / pop_5_17
    )
}

saipe <- map(saipe_years, read_saipe) |> list_rbind()

# write --------------------------------------------------------------------------

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
write_csv(acs_clean, "data/processed/acs_district.csv")
write_csv(saipe, "data/processed/saipe_district.csv")

message("ACS rows: ", nrow(acs_clean), " (", sum(acs_clean$geo_level == "District"),
        " districts); SAIPE rows by year: ",
        paste(count(saipe, saipe_year)$n, collapse = ", "))
