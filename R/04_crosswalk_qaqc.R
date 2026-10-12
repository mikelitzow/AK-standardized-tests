# Link DEED districts to Census/NCES district IDs, build a one-row-per-district
# indicator table, and run QA/QC checks on the AK STAR, science, NAEP and
# Census data.
#
# Inputs: data/processed/ files written by R/01-03.
# Outputs: data/processed/district_crosswalk.csv
#          data/processed/district_indicators.csv
#          QA/QC summary printed to the console (logs/04_crosswalk_qaqc.log)
# Run from the project root.

library(tidyverse)

akstar_grade <- read_csv("data/processed/akstar_grade.csv", show_col_types = FALSE)
akstar_sub <- read_csv("data/processed/akstar_subgroup.csv", show_col_types = FALSE)
akstar_districts <- read_csv("data/processed/akstar_districts.csv", show_col_types = FALSE)
science_grade <- read_csv("data/processed/science_grade.csv", show_col_types = FALSE)
science_sub <- read_csv("data/processed/science_subgroup.csv", show_col_types = FALSE)
science_districts <- read_csv("data/processed/science_districts.csv", show_col_types = FALSE)
naep <- read_csv("data/processed/naep_states.csv", show_col_types = FALSE)
naep_log <- read_csv("data/raw/naep/naep_call_log.csv", show_col_types = FALSE)
acs <- read_csv("data/processed/acs_district.csv", show_col_types = FALSE)
saipe <- read_csv("data/processed/saipe_district.csv", show_col_types = FALSE)

section <- function(x) cat("\n\n==== ", x, " ", strrep("=", max(3, 60 - nchar(x))), "\n", sep = "")
check <- function(desc, ok) {
  n_fail <- sum(!ok, na.rm = TRUE)
  n_na <- sum(is.na(ok))
  cat(sprintf("[%s] %s%s%s\n", if (n_fail == 0 && n_na == 0) "PASS" else "FAIL", desc,
              if (n_fail > 0) sprintf(" (%d of %d fail)", n_fail, length(ok)) else "",
              if (n_na > 0) sprintf(" (%d NA)", n_na) else ""))
}
show <- function(x, n = 100) print(x, n = n, width = 200)

# crosswalk ---------------------------------------------------------------------

census_names <- saipe |>
  arrange(desc(saipe_year)) |>
  distinct(leaid, census_name)

# DEED names that differ from Census names; Mount Edgecumbe is a statewide
# boarding school with no geographic district
name_fixes <- c(
  "Nome Public Schools" = "Nome School District",
  "Wrangell Public School District" = "Wrangell School District",
  "Saint Mary's School District" = "St. Marys City School District"
)

crosswalk <- bind_rows(akstar_districts, science_districts) |>
  distinct(district_id, district_name) |>
  mutate(census_name = coalesce(name_fixes[district_name], district_name)) |>
  left_join(census_names, by = "census_name") |>
  arrange(district_name)

section("Crosswalk: DEED districts to Census LEAIDs")
check("each DEED district ID has one name across years",
      !any(duplicated(crosswalk$district_id)))
cat("DEED districts with no Census match:\n")
show(filter(crosswalk, is.na(leaid)) |> select(district_id, district_name))
cat("Census districts with no DEED match:\n")
show(anti_join(census_names, crosswalk, by = "leaid"))
cat("DEED districts listed per year:\n")
show(count(akstar_districts, year))
cat("Districts not listed in every year:\n")
show(akstar_districts |> count(district_id, district_name) |>
       filter(n < n_distinct(akstar_districts$year)))

# AK STAR and science --------------------------------------------------------------

qa_test <- function(grade_df, sub_df, name) {
  section(paste0(name, ": coverage"))
  show(grade_df |> count(year, level, grade) |>
         pivot_wider(names_from = grade, values_from = n))
  cat("Subgroup rows by year and level:\n")
  show(count(sub_df, year, level))
  cat("Subgroups listed:\n")
  show(count(sub_df, subgroup) |> arrange(desc(n)), n = 40)

  section(paste0(name, ": suppression"))
  cat("Raw percentage values that are not plain numbers:\n")
  show(bind_rows(grade_df, sub_df) |>
         filter(!str_detect(prof_pct_raw, "^[0-9.]+%$")) |>
         count(prof_pct_raw, sort = TRUE))
  cat("Share of district cells suppressed or reported as a range (all students):\n")
  show(grade_df |> filter(level == "District") |>
         group_by(year, grade) |>
         summarise(cells = n(), pct_suppressed = round(100 * mean(suppressed), 1),
                   pct_range = round(100 * mean(pct_is_range), 1), .groups = "drop") |>
         pivot_wider(names_from = year, values_from = c(pct_suppressed, pct_range)))

  section(paste0(name, ": internal consistency"))
  exact <- bind_rows(grade_df, sub_df) |> filter(!suppressed, !pct_is_range)
  check("proficient % = proficient n / tested (within 0.01)",
        abs(exact$prof_pct - 100 * exact$prof_n / (exact$prof_n + exact$notprof_n)) < 0.01)
  check("proficient % + not proficient % = 100 (within 0.02)",
        abs(exact$prof_pct + exact$notprof_pct - 100) < 0.02)
  # DEED's participation rate equals tested / enrollment exactly in 2026; in
  # 2023-2025 it was computed slightly differently for some rows
  part <- exact |>
    filter(enrollment > 0) |>
    mutate(dev = participation_pct - 100 * tested / enrollment)
  cat("Participation % minus tested / enrollment, by year (all rows with exact counts):\n")
  show(part |> group_by(year) |>
         summarise(rows = n(), off_by_1pt_plus = sum(abs(dev) >= 1),
                   max_abs_dev = round(max(abs(dev)), 1)))
  check("2026: participation % = tested / enrollment (within 0.01)",
        abs(filter(part, year == 2026)$dev) < 0.01)

  state_v_dist <- grade_df |>
    filter(grade == "All") |>
    group_by(year, subject) |>
    summarise(
      state_tested = sum(tested[level == "State"]),
      district_tested = sum(tested[level == "District"], na.rm = TRUE),
      district_recovered = sum(level == "District" & tested_from_participation),
      district_suppressed = sum(level == "District" & suppressed),
      state_enrolled = sum(enrollment[level == "State"]),
      district_enrolled = sum(enrollment[level == "District"]),
      .groups = "drop"
    ) |>
    mutate(tested_gap = state_tested - district_tested,
           enrolled_gap = state_enrolled - district_enrolled)
  cat("Statewide totals vs sum of districts (All Grades; range rows use recovered counts):\n")
  show(state_v_dist)
  check("district enrollments sum to the statewide enrollment",
        state_v_dist$enrolled_gap == 0)
  # residual gaps: suppressed districts (<5 tested each) and, before 2026,
  # recovered counts that are approximate
  check("district tested counts sum to statewide within 5 per suppressed or recovered district",
        abs(state_v_dist$tested_gap) <= 5 * pmax(1, state_v_dist$district_suppressed + (state_v_dist$year < 2026) * state_v_dist$district_recovered))

  grade_sum <- grade_df |>
    group_by(year, level, district_id, subject) |>
    summarise(all = tested[grade == "All"],
              by_grade = sum(tested[grade != "All"]),
              any_missing = any(is.na(tested) | tested_from_participation), .groups = "drop") |>
    filter(!any_missing)
  check("grade-level tested counts sum to All Grades (districts with exact counts)",
        grade_sum$all == grade_sum$by_grade)

  sub_all <- sub_df |>
    filter(subgroup == "All Students") |>
    select(year, level, district_id, subject, sub_prof_n = prof_n, sub_enr = enrollment) |>
    inner_join(grade_df |> filter(grade == "All") |>
                 select(year, level, district_id, subject, prof_n, enrollment),
               by = c("year", "level", "district_id", "subject"))
  check("subgroup page 'All Students' matches the main page",
        coalesce(sub_all$sub_prof_n == sub_all$prof_n, TRUE) & sub_all$sub_enr == sub_all$enrollment)

  section(paste0(name, ": statewide results by year (all students, all grades)"))
  show(grade_df |> filter(level == "State", grade == "All") |>
         select(year, subject, prof_pct, prof_n, notprof_n, enrollment, participation_pct))

  cat("District participation rates below 80% (all grades, first subject):\n")
  show(grade_df |> filter(level == "District", grade == "All", subject == first(subject),
                              participation_pct < 80) |>
         select(year, district_name, enrollment, participation_pct) |>
         arrange(participation_pct), n = 40)
}

qa_test(akstar_grade, akstar_sub, "AK STAR")
qa_test(science_grade, science_sub, "Science")

# NAEP --------------------------------------------------------------------------

section("NAEP: API calls")
show(naep_log |> count(subject, grade, ok, empty = n_rows == 0))
cat("Failed or empty calls:\n")
show(naep_log |> filter(!ok | n_rows == 0) |> select(subject, grade, year, variable, message), n = 50)

section("NAEP: coverage (all students, mean score)")
tot <- naep |> filter(variable == "TOTAL", stattype == "MN:MN")
show(tot |> group_by(subject, grade, year) |>
       summarise(jurisdictions = sum(!is.na(value)), alaska = !is.na(value[jurisdiction == "AK"]),
                 .groups = "drop") |>
       pivot_wider(names_from = c(subject, grade), values_from = c(jurisdictions, alaska),
                   names_vary = "slowest"))

section("NAEP: value checks")
check("mean scale scores between 150 and 350",
      between(tot$value, 150, 350) | is.na(tot$value))
alc <- naep |> filter(str_starts(stattype, "ALC"), variable == "TOTAL") |>
  select(subject, grade, year, sample, jurisdiction, stattype, value) |>
  pivot_wider(names_from = stattype, values_from = value)
check("achievement-level % between 0 and 100",
      naep |> filter(str_starts(stattype, "ALC")) |> pull(value) |> (\(v) between(v, 0, 100) | is.na(v))())
check("below Basic + at/above Basic = 100 (within 1)",
      abs(alc$`ALC:BB` + alc$`ALC:AB` - 100) < 1 | is.na(alc$`ALC:BB`))
alc_ok <- filter(alc, !is.na(`ALC:AB`), !is.na(`ALC:AP`), !is.na(`ALC:AD`))
check("at/above Basic >= at/above Proficient >= Advanced (rows with all three)",
      alc_ok$`ALC:AB` >= alc_ok$`ALC:AP` & alc_ok$`ALC:AP` >= alc_ok$`ALC:AD`)

cat("Alaska vs national public, mean score and % at/above Proficient:\n")
show(naep |> filter(variable == "TOTAL", jurisdiction %in% c("AK", "NP"),
                    stattype %in% c("MN:MN", "ALC:AP"), year >= 2003) |>
       select(subject, grade, year, jurisdiction, stattype, value) |>
       mutate(value = round(value, 1)) |>
       pivot_wider(names_from = c(jurisdiction, stattype), values_from = value), n = 60)

cat("Alaska rank among 50 states + DC, 2024 mean score (1 = highest):\n")
show(tot |> filter(year == 2024, !jurisdiction %in% c("NP", "DS")) |>
       group_by(subject, grade) |>
       mutate(rank = min_rank(desc(value)), n = sum(!is.na(value))) |>
       filter(jurisdiction == "AK") |>
       select(subject, grade, value, rank, n))

cat("Alaska subgroups reported (rows with a value), 2003-2024:\n")
show(naep |> filter(jurisdiction == "AK", stattype == "MN:MN", variable != "TOTAL") |>
       group_by(variable, var_value_label) |>
       summarise(years_reported = sum(!is.na(value)), of = n(), .groups = "drop"), n = 40)

# Census -------------------------------------------------------------------------

section("Census: ACS 2020-2024 and SAIPE")
acs_d <- filter(acs, geo_level == "District")
check("ACS has 53 Alaska districts", nrow(acs_d) == 53)
acs_d <- acs_d |>
  mutate(income_cv = 100 * (med_hh_income_moe / 1.645) / med_hh_income,
         ba_cv = 100 * (pct_ba_plus_moe / 1.645) / pct_ba_plus)
cat("Median household income: top-coded or with CV > 30% (unreliable):\n")
show(acs_d |> filter(med_hh_income_topcoded | income_cv > 30) |>
       left_join(census_names, by = "leaid") |>
       select(census_name, med_hh_income, med_hh_income_moe, income_cv) |>
       arrange(desc(income_cv)))
cat("CV summary (%), median household income and % bachelor's+:\n")
show(acs_d |> summarise(across(c(income_cv, ba_cv),
                               list(median = \(x) median(x, na.rm = TRUE),
                                    max = \(x) max(x, na.rm = TRUE),
                                    n_over_30 = \(x) sum(x > 30, na.rm = TRUE)))))

cat("SAIPE districts by year:\n")
show(count(saipe, saipe_year))
check("SAIPE child poverty % between 0 and 100", between(saipe$child_poverty_pct, 0, 100))
cat("SAIPE child poverty %, 2024 (highest and lowest):\n")
s24 <- saipe |> filter(saipe_year == 2024) |> arrange(desc(child_poverty_pct))
show(bind_rows(head(s24, 5), tail(s24, 5)) |>
       select(census_name, pop_5_17, pov_5_17, child_poverty_pct))

# district indicator table ---------------------------------------------------------

# DEED's own economic measure: share of AK STAR-enrolled students (grades 3-9)
# who are economically disadvantaged
econdis <- akstar_sub |>
  filter(level == "District", subject == "ELA",
         subgroup %in% c("All Students", "Economically Disadvantaged")) |>
  select(year, district_id, subgroup, enrollment) |>
  pivot_wider(names_from = subgroup, values_from = enrollment) |>
  transmute(year, district_id,
            econdis_pct = 100 * `Economically Disadvantaged` / `All Students`)

indicators <- crosswalk |>
  left_join(acs_d |> select(leaid, med_hh_income, med_hh_income_moe, med_hh_income_topcoded,
                            per_capita_income, per_capita_income_moe,
                            pct_hs_plus, pct_ba_plus, pct_ba_plus_moe),
            by = "leaid") |>
  left_join(saipe |> filter(saipe_year == 2024) |>
              select(leaid, pop_total, pop_5_17, child_poverty_pct_2024 = child_poverty_pct),
            by = "leaid") |>
  left_join(saipe |> group_by(leaid) |>
              summarise(child_poverty_pct_2022_24 = 100 * sum(pov_5_17) / sum(pop_5_17)),
            by = "leaid") |>
  left_join(econdis |> group_by(district_id) |>
              summarise(econdis_pct_mean = mean(econdis_pct, na.rm = TRUE),
                        econdis_pct_2026 = econdis_pct[year == max(year)]),
            by = "district_id")

# Districts running large statewide correspondence (home-school) programs
# enroll students who live anywhere in Alaska, so local Census measures do not
# describe their students. Compare AK STAR enrollment (grades 3-9) with the
# district's own children of that age (SAIPE ages 5-17 x 7/13).
local_ratio <- akstar_grade |>
  filter(level == "District", grade == "All", subject == "ELA") |>
  group_by(district_id) |>
  summarise(enrollment_3_9_mean = mean(enrollment),
            participation_pct_mean = mean(participation_pct)) |>
  left_join(crosswalk |> select(district_id, leaid), by = "district_id") |>
  left_join(saipe |> group_by(leaid) |> summarise(pop_5_17_mean = mean(pop_5_17)),
            by = "leaid") |>
  transmute(district_id, enrollment_3_9_mean, participation_pct_mean,
            enrollment_to_local_children = enrollment_3_9_mean / (pop_5_17_mean * 7 / 13),
            nonlocal_enrollment = enrollment_to_local_children > 2)

indicators <- indicators |> left_join(local_ratio, by = "district_id")

write_csv(crosswalk, "data/processed/district_crosswalk.csv")
write_csv(indicators, "data/processed/district_indicators.csv")

section("Economic indicators: coverage and correlations")
cat("Districts in indicator table:", nrow(indicators), "\n")
show(indicators |> summarise(across(c(med_hh_income, per_capita_income, pct_ba_plus,
                                      child_poverty_pct_2024, econdis_pct_mean),
                                    \(x) sum(!is.na(x)))))
cat("Spearman correlations among indicators (districts with all values):\n")
print(round(cor(indicators |>
                  filter(!med_hh_income_topcoded) |>
                  select(med_hh_income, per_capita_income, pct_ba_plus,
                         child_poverty_pct_2022_24, econdis_pct_mean),
                use = "complete.obs", method = "spearman"), 2))

# correlation of each indicator with district proficiency (ELA + math, all
# grades, pooled over years; range rows enter at the midpoint of their bound)
prof <- akstar_grade |>
  filter(level == "District", grade == "All", !suppressed) |>
  mutate(pct = coalesce(prof_pct, (prof_pct_min + prof_pct_max) / 2)) |>
  group_by(district_id) |>
  summarise(prof_pct = weighted.mean(pct, tested), tested = sum(tested))
cat("\nDistricts flagged for non-local enrollment (enrollment > 2x local children):\n")
show(indicators |> filter(nonlocal_enrollment) |>
       select(district_name, enrollment_3_9_mean, enrollment_to_local_children,
              participation_pct_mean) |>
       arrange(desc(enrollment_to_local_children)))

prof_cor <- function(d) {
  d |>
    inner_join(prof, by = "district_id") |>
    summarise(n = n(), across(c(med_hh_income, per_capita_income, pct_ba_plus,
                                child_poverty_pct_2022_24, econdis_pct_mean),
                              \(x) round(cor(x, prof_pct, use = "complete.obs", method = "spearman"), 2)))
}
cat("\nSpearman correlation of each indicator with district % proficient (2023-2026 pooled):\n")
usable <- indicators |> filter(!coalesce(med_hh_income_topcoded, FALSE))
show(bind_rows(
  prof_cor(usable) |> mutate(districts = "all with Census data", .before = 1),
  prof_cor(filter(usable, !nonlocal_enrollment)) |>
    mutate(districts = "excluding non-local enrollment", .before = 1)
))
