# Which districts like Kodiak (similar child poverty and size) sit
# consistently above the poverty regression lines?
#
# For every district: residual from the line fit to all non-local districts
# (as in R/05), for ELA, math and science; pooled over years, by year, and by
# grade. Prints districts with child poverty 3-13% and grades 3-9 enrollment
# 150-11,000, and writes the full table.
#
# Inputs: data/processed/akstar_grade.csv, science_grade.csv, district_indicators.csv
# Output: data/processed/kodiak_peer_residuals.csv
# Run from the project root.

library(tidyverse)

results <- bind_rows(read_csv("data/processed/akstar_grade.csv", show_col_types = FALSE),
                     read_csv("data/processed/science_grade.csv", show_col_types = FALSE))
districts <- read_csv("data/processed/district_indicators.csv", show_col_types = FALSE) |>
  filter(!is.na(child_poverty_pct_2022_24)) |>
  transmute(district_id, district_name, pov = child_poverty_pct_2022_24,
            enrollment = enrollment_3_9_mean, participation = participation_pct_mean,
            nonlocal = nonlocal_enrollment)

# pooled % proficient as in R/05: suppressed rows drop out, ranges at midpoint
pool_prof <- function(d, ...) {
  d |>
    filter(level == "District", !suppressed) |>
    mutate(pct = coalesce(prof_pct, (prof_pct_min + prof_pct_max) / 2)) |>
    group_by(district_id, subject, ...) |>
    summarise(prof = sum(pct * tested) / sum(tested), .groups = "drop") |>
    inner_join(districts, by = "district_id")
}

# line fit without the non-local districts; residuals for every district
add_resid <- function(d) {
  m <- lm(prof ~ pov, filter(d, !nonlocal))
  mutate(d, resid = prof - predict(m, d))
}

pooled <- results |> filter(grade == "All") |> pool_prof() |>
  group_by(subject) |> group_modify(\(d, k) add_resid(d)) |> ungroup()
yearly <- results |> filter(grade == "All") |> pool_prof(year) |>
  group_by(subject, year) |> group_modify(\(d, k) add_resid(d)) |> ungroup()
by_grade <- results |> filter(grade != "All") |> pool_prof(grade) |>
  group_by(subject, grade) |> group_modify(\(d, k) add_resid(d)) |> ungroup()

peer_table <- pooled |>
  select(district_id, district_name, pov, enrollment, participation, nonlocal, subject, resid) |>
  pivot_wider(names_from = subject, values_from = resid, names_prefix = "resid_") |>
  left_join(yearly |> group_by(district_id) |>
              summarise(subject_years_above = sum(resid > 0), subject_years = n()),
            by = "district_id") |>
  left_join(by_grade |> group_by(district_id) |>
              summarise(grade_fits_above = sum(resid > 0), grade_fits = n(),
                        resid_ela9 = resid[subject == "ELA" & grade == "9"][1],
                        resid_math9 = resid[subject == "Math" & grade == "9"][1],
                        resid_sci10 = resid[subject == "Science" & grade == "10"][1]),
            by = "district_id") |>
  mutate(resid_mean = (resid_ELA + resid_Math + resid_Science) / 3) |>
  arrange(desc(resid_mean))

write_csv(peer_table, "data/processed/kodiak_peer_residuals.csv")

cat("Districts with child poverty 3-13% and grades 3-9 enrollment 150-11,000:\n")
peer_table |>
  filter(between(pov, 3, 13), between(enrollment, 150, 11000)) |>
  mutate(across(where(is.double), \(x) round(x, 1)),
         district_name = str_remove(district_name, " School District$| Public Schools$")) |>
  select(district_name, pov, enrollment, participation, nonlocal, resid_ELA, resid_Math,
         resid_Science, subject_years_above, subject_years, grade_fits_above, grade_fits,
         resid_ela9, resid_math9, resid_sci10) |>
  print(n = 40, width = 250)
