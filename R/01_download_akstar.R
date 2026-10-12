# Download and parse results for the state and every Alaska school district
# from DEED's assessment-results web app:
# - AK STAR (ELA and math, grades 3-9), spring 2023-2026 -> akstar_*.csv
# - Alaska Science Assessment (grades 5, 8, 10), spring 2022-2026 -> science_*.csv
#
# DEED does not post bulk files, so this script saves each results page to
# data/raw/{akstar,science}/html/ (re-runs only fetch pages not already
# cached) and parses the tables into tidy CSVs in data/processed/.
#
# Source: https://education.alaska.gov/assessments/results
# Run from the project root.

library(tidyverse)
library(httr2)
library(rvest)

# AK STAR cut scores changed in January 2024 and 2023 was released under the
# new ones, so 2023-2026 are comparable; science is unchanged since 2022
akstar_years <- c("2022-2023", "2023-2024", "2024-2025", "2025-2026")
science_years <- c("2021-2022", akstar_years)

# grades to pull subgroup breakdowns for; add "3rd Grade", ..., "9th Grade"
# for grade-level subgroups (about 8x the requests)
subgroup_grades <- c("All Grades")

# DEED IDs of districts no longer in the dropdown (53 = Tanana City, which
# reported results through 2023-24)
closed_district_ids <- c(53)

base <- "https://education.alaska.gov/assessment-results"
ua <- "R httr2 (AK-standardized-tests public data project)"
cookie_file <- tempfile(fileext = ".txt")
pause <- 1 # seconds between requests

# fetch ----------------------------------------------------------------------

get_page <- function(url, referer = NULL) {
  req <- request(url) |>
    req_user_agent(ua) |>
    req_cookie_preserve(cookie_file) |>
    req_retry(max_tries = 3) |>
    req_error(is_error = \(resp) FALSE)
  if (!is.null(referer)) req <- req_headers(req, Referer = referer)
  req_perform(req)
}

page_ok <- function(resp) {
  body <- resp_body_string(resp)
  resp_status(resp) == 200 &&
    !str_detect(body, "An error occurred while processing your request") &&
    !str_detect(body, "Request Rejected")
}

# download url to path unless cached; DEED's subgroup pages need a live
# session cookie, so a failed request re-opens the referring page and retries
fetch <- function(url, path, referer = NULL, tries = 3) {
  if (file.exists(path)) return(TRUE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(tries)) {
    Sys.sleep(pause)
    resp <- get_page(url, referer)
    if (page_ok(resp)) {
      writeBin(resp_body_raw(resp), path)
      return(TRUE)
    }
    Sys.sleep(pause)
    get_page(referer %||% paste0(base, "/Statewide/StatewideResults?schoolYear=2025-2026&isScience=False"))
  }
  warning("Failed after ", tries, " tries: ", url)
  FALSE
}

abs_url <- function(href) paste0("https://education.alaska.gov", href)

# parse ----------------------------------------------------------------------

# every results table (state, district, subgroup) has the same columns:
# label | proficient n | proficient % | not proficient n | not proficient % |
# enrollment | participation rate | [link to subgroup page]
parse_tables <- function(path) {
  h <- read_html(path)
  title <- html_text2(html_element(h, "h1"))
  tbls <- html_elements(h, "table.table-striped")
  map(tbls, function(tb) {
    heading <- html_text2(html_element(tb, xpath = "preceding::h3[1]"))
    rows <- html_elements(tb, "tbody tr")
    cells <- map(rows, \(r) html_text2(html_elements(r, "td")))
    tibble(
      page_title = title,
      heading = heading,
      label = map_chr(cells, 1),
      prof_n_raw = map_chr(cells, 2),
      prof_pct_raw = map_chr(cells, 3),
      notprof_n_raw = map_chr(cells, 4),
      notprof_pct_raw = map_chr(cells, 5),
      enrollment_raw = map_chr(cells, 6),
      participation_raw = map_chr(cells, 7),
      link = map_chr(rows, \(r) html_attr(html_element(r, "a"), "href"))
    )
  }) |>
    list_rbind()
}

num <- function(x) suppressWarnings(parse_number(x, na = c("*", "", "N/A", "n/a")))

tidy_values <- function(d) {
  d |>
    mutate(
      suppressed = prof_pct_raw == "*",
      pct_is_range = !suppressed & str_detect(prof_pct_raw, "[<>≤≥]|more|fewer"),
      prof_n = num(prof_n_raw),
      notprof_n = num(notprof_n_raw),
      prof_pct = num(prof_pct_raw),
      notprof_pct = num(notprof_pct_raw),
      # ranges read "90% or more" / "10% or fewer"; keep them as bounds
      prof_pct_min = case_when(
        str_detect(prof_pct_raw, "more") ~ prof_pct,
        str_detect(prof_pct_raw, "fewer") ~ 0,
        TRUE ~ prof_pct
      ),
      prof_pct_max = case_when(
        str_detect(prof_pct_raw, "more") ~ 100,
        str_detect(prof_pct_raw, "fewer") ~ prof_pct,
        TRUE ~ prof_pct
      ),
      # an exact percentage is only meaningful when not a range
      prof_pct = if_else(pct_is_range, NA_real_, prof_pct),
      notprof_pct = if_else(pct_is_range, NA_real_, notprof_pct),
      enrollment = num(enrollment_raw),
      participation_pct = num(participation_raw),
      # counts are withheld for range rows; recover the number tested from
      # participation x enrollment (exact in 2026, within a few students before)
      tested_from_participation = is.na(prof_n) & !suppressed,
      tested = if_else(tested_from_participation,
                       round(participation_pct * enrollment / 100),
                       prof_n + notprof_n)
    )
}

grade_code <- function(x) {
  x <- str_remove(x, " \\(.*\\)$")
  if_else(x == "All Grades", "All", str_extract(x, "^\\d+"))
}

subject_code <- function(x) {
  case_when(
    str_detect(x, "English Language Arts|\\(ELA\\)|ELA") ~ "ELA",
    str_detect(x, "Mathematics|Math") ~ "Math",
    str_detect(x, "Science") ~ "Science"
  )
}

# run ------------------------------------------------------------------------

# scrape the state page, every district page and the linked subgroup pages for
# one test (AK STAR or the Alaska Science Assessment) over the given years
scrape_test <- function(school_years, science, cache) {
  flag <- if (science) "True" else "False"
  grade_rows <- list()
  subgroup_rows <- list()
  district_lists <- list()

  for (sy in school_years) {
    ydir <- file.path(cache, sy)
    message("== ", if (science) "Science " else "AK STAR ", sy)

    # district list for this year
    sel_url <- paste0(base, "/District/DistrictSelect?schoolYear=", sy, "&isScience=", flag)
    sel_path <- file.path(ydir, "district_select.html")
    fetch(sel_url, sel_path)
    opts <- read_html(sel_path) |> html_elements("select#DistrictId option")
    districts <- tibble(
      school_year = sy,
      district_id = as.integer(html_attr(opts, "value")),
      district_name = html_text2(opts)
    )
    # the dropdown lists current districts only; also try districts that have
    # since closed and keep them in years where DEED has a results page
    for (id in setdiff(closed_district_ids, districts$district_id)) {
      path <- file.path(ydir, sprintf("district_%03d.html", id))
      fetch(paste0(base, "/District/DistrictResults?DistrictYear=", sy,
                   "&IsScience=", flag, "&DistrictId=", id), path)
      page <- read_html(path)
      title <- html_text2(html_element(page, "h1"))
      name <- str_squish(str_remove(str_remove(title, fixed(sy)), "Results$"))
      if (nchar(name) > 0 && length(html_elements(page, "table.table-striped")) > 0) {
        districts <- add_row(districts, school_year = sy, district_id = id, district_name = name)
      }
    }
    district_lists[[sy]] <- districts

    # statewide page, then each district page
    pages <- bind_rows(
      tibble(
        level = "State", district_id = NA_integer_, district_name = "Alaska",
        url = paste0(base, "/Statewide/StatewideResults?schoolYear=", sy, "&isScience=", flag),
        path = file.path(ydir, "statewide.html")
      ),
      districts |>
        transmute(
          level = "District", district_id, district_name,
          url = paste0(base, "/District/DistrictResults?DistrictYear=", sy,
                       "&IsScience=", flag, "&DistrictId=", district_id),
          path = file.path(ydir, sprintf("district_%03d.html", district_id))
        )
    )

    for (i in seq_len(nrow(pages))) {
      p <- pages[i, ]
      if (!fetch(p$url, p$path)) next
      if (length(html_elements(read_html(p$path), "table.table-striped")) == 0) next
      tb <- parse_tables(p$path) |>
        mutate(school_year = sy, level = p$level,
               district_id = p$district_id, district_name = p$district_name)
      grade_rows[[length(grade_rows) + 1]] <- tb

      # subgroup pages linked from this page
      sub_links <- tb |>
        filter(!is.na(link), heading %in% subgroup_grades) |>
        mutate(subject = subject_code(label))
      for (j in seq_len(nrow(sub_links))) {
        s <- sub_links[j, ]
        s_path <- file.path(ydir, sprintf(
          "%s_sub_%s_%s.html",
          if (p$level == "State") "statewide" else sprintf("district_%03d", p$district_id),
          str_replace_all(s$heading, " ", ""), s$subject
        ))
        if (!fetch(abs_url(s$link), s_path, referer = p$url)) next
        subgroup_rows[[length(subgroup_rows) + 1]] <- parse_tables(s_path) |>
          mutate(school_year = sy, level = p$level,
                 district_id = p$district_id, district_name = p$district_name)
      }
    }
  }

  year_from_sy <- function(sy) as.integer(str_sub(sy, 6, 9)) # spring test year

  list(
    grade = bind_rows(grade_rows) |>
      tidy_values() |>
      transmute(
        year = year_from_sy(school_year), school_year, level, district_id, district_name,
        grade = grade_code(heading), subject = subject_code(label),
        prof_n, notprof_n, tested, tested_from_participation, prof_pct, notprof_pct, enrollment, participation_pct,
        prof_pct_min, prof_pct_max, suppressed, pct_is_range, prof_pct_raw, notprof_pct_raw
      ),
    subgroup = bind_rows(subgroup_rows) |>
      tidy_values() |>
      transmute(
        year = year_from_sy(school_year), school_year, level, district_id, district_name,
        grade = grade_code(heading), subject = subject_code(heading), subgroup = label,
        prof_n, notprof_n, tested, tested_from_participation, prof_pct, notprof_pct, enrollment, participation_pct,
        prof_pct_min, prof_pct_max, suppressed, pct_is_range, prof_pct_raw, notprof_pct_raw
      ),
    districts = bind_rows(district_lists) |>
      mutate(year = year_from_sy(school_year), .before = 1)
  )
}

write_test <- function(res, prefix) {
  dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
  write_csv(res$grade, sprintf("data/processed/%s_grade.csv", prefix))
  write_csv(res$subgroup, sprintf("data/processed/%s_subgroup.csv", prefix))
  write_csv(res$districts, sprintf("data/processed/%s_districts.csv", prefix))
  message(prefix, "_grade: ", nrow(res$grade), " rows; ", prefix, "_subgroup: ",
          nrow(res$subgroup), " rows; districts by year: ",
          paste(count(res$districts, year)$n, collapse = ", "))
}

scrape_test(akstar_years, science = FALSE, cache = "data/raw/akstar/html") |>
  write_test("akstar")
scrape_test(science_years, science = TRUE, cache = "data/raw/science/html") |>
  write_test("science")
