# Download NAEP (Nation's Report Card) state results for reading and math,
# grades 4 and 8, for all 50 states, DC, DoDEA schools and national public.
#
# NAEP reports results for states and for 26 large urban districts (TUDA);
# no Alaska district is in TUDA, so there are no Kodiak (or other Alaska
# district) NAEP results.
#
# Source: NAEP Data Service API, https://www.nationsreportcard.gov/api_documentation.aspx
# Run from the project root.

library(tidyverse)
library(httr2)

api <- "https://www.nationsreportcard.gov/DataService/GetAdhocData.aspx"
juris <- c(state.abb, "DC", "DS", "NP") # DS = DoDEA, NP = national public

# statistics: mean scale score and cumulative achievement-level percentages
stattypes <- c("MN:MN", "ALC:BB", "ALC:AB", "ALC:AP", "ALC:AD")

# TOTAL = all students; ECONDIS = economically disadvantaged status
# (NSLP eligibility before 2024); SDRACE = race/ethnicity
variables <- c("TOTAL", "ECONDIS", "SDRACE", "GENDER")

# state-level assessment years; state results before 2000 (math) and 1998
# (reading) come from the "accommodations not permitted" R2 sample, which is
# the only one with state data in those years (Alaska: 1996 math)
calls <- bind_rows(
  tibble(subject = "mathematics", subscale = "MRPCM", grade = 4,
         year = c("1992R2", "1996R2", "2000", "2003", "2005", "2007", "2009",
                  "2011", "2013", "2015", "2017", "2019", "2022", "2024")),
  tibble(subject = "mathematics", subscale = "MRPCM", grade = 8,
         year = c("1990R2", "1992R2", "1996R2", "2000", "2003", "2005", "2007",
                  "2009", "2011", "2013", "2015", "2017", "2019", "2022", "2024")),
  tibble(subject = "reading", subscale = "RRPCM", grade = 4,
         year = c("1992R2", "1994R2", "1998", "2002", "2003", "2005", "2007",
                  "2009", "2011", "2013", "2015", "2017", "2019", "2022", "2024")),
  tibble(subject = "reading", subscale = "RRPCM", grade = 8,
         year = c("1998", "2002", "2003", "2005", "2007", "2009", "2011",
                  "2013", "2015", "2017", "2019", "2022", "2024"))
) |>
  cross_join(tibble(variable = variables))

naep_call <- function(subject, subscale, grade, year, variable) {
  resp <- request(api) |>
    req_url_query(
      type = "data", subject = subject, grade = grade, subscale = subscale,
      variable = variable, jurisdiction = paste(juris, collapse = ","),
      stattype = paste(stattypes, collapse = ","), Year = year,
      ShowDetails = "true"
    ) |>
    req_timeout(120) |>
    req_retry(max_tries = 3) |>
    req_error(is_error = \(resp) FALSE) |>
    req_perform()
  txt <- resp_body_string(resp)
  out <- tryCatch(jsonlite::fromJSON(txt), error = \(e) NULL)
  ok <- !is.null(out) && identical(as.integer(out$status), 200L) && is.data.frame(out$result)
  list(
    ok = ok,
    message = if (ok) "" else str_sub(str_squish(txt), 1, 200),
    data = if (ok) as_tibble(out$result) else NULL
  )
}

log_rows <- list()
data_rows <- list()
for (i in seq_len(nrow(calls))) {
  cl <- calls[i, ]
  res <- naep_call(cl$subject, cl$subscale, cl$grade, cl$year, cl$variable)
  n <- if (res$ok) nrow(res$data) else 0L
  log_rows[[i]] <- mutate(cl, ok = res$ok, n_rows = n, message = res$message)
  if (n > 0) data_rows[[length(data_rows) + 1]] <- res$data
  message(sprintf("%3d/%d %s g%d %s %s: %s rows", i, nrow(calls), cl$subject,
                  cl$grade, cl$year, cl$variable, n))
  Sys.sleep(0.5)
}

call_log <- bind_rows(log_rows)
raw <- bind_rows(data_rows)

dir.create("data/raw/naep", showWarnings = FALSE, recursive = TRUE)
write_csv(call_log, "data/raw/naep/naep_call_log.csv")
write_csv(raw, "data/raw/naep/naep_api_raw.csv")

naep <- raw |>
  transmute(
    year, sample, subject = recode(subject, MAT = "Math", RED = "Reading"),
    grade, scale, jurisdiction, juris_label = jurisLabel,
    variable, variable_label = variableLabel,
    var_value = varValue, var_value_label = varValueLabel,
    stattype, value, se = stdError,
    displayable = isStatDisplayable == 1,
    # 999 marks statistics NAEP does not report (reporting standards not met)
    value = if_else(displayable, value, NA_real_),
    se = if_else(displayable, se, NA_real_)
  ) |>
  arrange(subject, grade, variable, jurisdiction, year, var_value, stattype)

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
write_csv(naep, "data/processed/naep_states.csv")

message("Calls: ", nrow(call_log), "; failed: ", sum(!call_log$ok),
        "; empty: ", sum(call_log$ok & call_log$n_rows == 0),
        "; rows: ", nrow(naep))
