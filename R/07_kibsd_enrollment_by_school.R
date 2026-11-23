# Kodiak Island Borough School District (KIBSD) enrollment by school, school
# years 2016-17 to 2025-26, plus ADM by school for 2025-26 and (preliminary)
# 2026-27, with totals for the town schools and year-on-year change by group.
#
# DEED publishes average daily membership (ADM) by district only. ADM by school
# is in KIBSD's budget documents (the foundation formula pages), and the ones
# posted on kibsd.org cover 2025-26 and 2026-27 only. For earlier years the
# public count by school is October 1 enrollment, taken during the same fall
# count period (ADM averages the 20 school days ending the fourth Friday in
# October). District-wide, October 1 K-12 enrollment is compared with ADM below.
#
# Sources (DEED Statistics & Reports, https://education.alaska.gov/stats):
#   2016-17, 2017-18: School Enrollment by Grade as of October 1 (pdf)
#   2018-19, 2019-20: Teacher and Student Counts by School (xlsx, totals only)
#   2020-21 to 2025-26: Enrollment by School by Grade (xlsx)
#   Average Daily Membership by District FY1988-FY2026 (xlsx, School Finance)
# 2025-26 ADM by school: KIBSD FY26 winter budget revision (updated 1/17/2026),
#   foundation formula page (read from the pdf)
# 2026-27: preliminary ADM by school from the KIBSD Board Retreat packet,
#   October 31, 2026, p. 22 (transcribed below; the table is an image)
# Town schools follow KIBSD's FY26 budget book: East, Main, North Star (closed
# after 2024-25), Peterson, Kodiak Middle and Kodiak High, plus the AKTEACH
# homeschool program, which is kept separate from the school buildings here.
#
# Outputs: data/processed/kibsd_enrollment_by_school.csv
#          figs/kibsd_town_enrollment_total.png
#          figs/kibsd_town_enrollment_by_school.png
#          figs/kibsd_enrollment_yoy_change.png
# Run from the project root.

library(tidyverse)
library(httr2)
library(readxl)

raw_dir <- "data/raw/deed_enrollment"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
ua <- "R httr2 (AK-standardized-tests public data project)"
deed <- "https://education.alaska.gov"
grade_years <- 2020:2025
school_year <- function(fall) sprintf("%d–%02d", fall, (fall + 1) %% 100)

# downloads ----------------------------------------------------------------------

sources <- tribble(
  ~file,                                     ~path,
  "school_enrollment_fy2017.pdf",            "/stats/SchoolEnrollment/2017SchoolEnrollment.pdf",
  "school_enrollment_fy2018.pdf",            "/stats/SchoolEnrollment/2018SchoolEnrollment.pdf",
  "teacher_student_2018-19.xlsx",            "/Stats/SchoolLevel/TeacherStudentData2018-2019_071520_forweb.xlsx",
  "teacher_student_2019-20.xlsx",            "/Stats/SchoolLevel/TeacherStudentData2019-2020_071520_forweb.xlsx",
  "teacher_student_2020-21.xlsx",            "/Stats/SchoolLevel/Teacher Student Data 2020-2021_032321_forweb.xlsx",
  "adm_history_district_fy1988_fy2026.xlsx", "/schoolfinance/docs/2025-09-09_Report_$ADMHistoryFY1988-FY2025.xlsx"
) |>
  bind_rows(tibble(yr = str_replace(school_year(grade_years), "–", "-"),
                   file = sprintf("school_by_grade_%s.xlsx", yr),
                   path = sprintf("/Stats/enrollment/2- Enrollment by School by Grade %s.xlsx", yr)) |>
              select(-yr))

fetch <- function(file, path) {
  out <- file.path(raw_dir, file)
  if (!file.exists(out)) {
    request(paste0(deed, URLencode(path))) |> req_user_agent(ua) |> req_perform(path = out)
    Sys.sleep(1)
  }
  out
}
walk2(sources$file, sources$path, fetch)

# KIBSD's FY26 winter budget revision (R/08 uses the same file)
kibsd_dir <- "data/raw/kibsd_finance"
winter_file <- file.path(kibsd_dir, "WINTER-REVISIONS-REVENUE-3-PAGE.pdf")
if (!file.exists(winter_file)) {
  dir.create(kibsd_dir, showWarnings = FALSE, recursive = TRUE)
  request("https://www.kibsd.org/wp-content/uploads/2026/01/WINTER-REVISIONS-REVENUE-3-PAGE.pdf") |>
    req_user_agent(ua) |> req_perform(path = winter_file)
}

# parsers: each returns fall (start year of the school year), school, k12, pk12;
# the district total comes back as school "District Total" --------------------------

# pdf: Kodiak block runs from the district total line to the next district (Kuspuk);
# school rows are a name followed by 16 counts (PK, KG, 1-12, total KG-12, total PK-12)
read_enrollment_pdf <- function(file, fall) {
  lines <- unlist(str_split(pdftools::pdf_text(file), "\n"))
  start <- str_which(lines, "^Kodiak Island Borough Schools")
  end <- str_which(lines, "^Kuspuk Schools")[1]
  m <- str_match(lines[start:(end - 1)], "^\\s*(\\S.*?)\\s+((?:\\d+\\s+){15}\\d+)\\s*$")
  m <- m[!is.na(m[, 1]), , drop = FALSE]
  counts <- str_split(m[, 3], "\\s+")
  tibble(fall, school = if_else(str_starts(m[, 2], "Kodiak Island"), "District Total", m[, 2]),
         k12 = map_dbl(counts, \(x) as.numeric(x[15])), pk12 = map_dbl(counts, \(x) as.numeric(x[16])))
}

read_counts_xlsx <- function(file, fall) {
  read_excel(file, skip = 1, .name_repair = "unique_quiet") |>
    filter(`District Name` == "Kodiak Island") |>
    transmute(fall, school = `School Name`, k12 = `Total Student KG-12`, pk12 = `Total Student PK-12`)
}

# two layouts: 2020-21 to 2022-23 (ID, District, School Name, ...) and 2023-24 on
# (Type, id, District/School, ...); the last two columns are the totals. KIBSD is
# district id 28 and its schools are 28xxxx.
read_grade_xlsx <- function(file, fall) {
  d <- read_excel(file, col_names = FALSE, col_types = "text", .name_repair = "unique_quiet")
  hdr <- which(apply(d, 1, \(r) "KG" %in% r))[1]
  names(d) <- make.unique(str_squish(unlist(d[hdr, ])))
  d <- d[-seq_len(hdr), ]
  id_col <- str_subset(names(d), regex("^id$", ignore_case = TRUE))[1]
  name_col <- str_subset(names(d), "School")[1]
  totals <- names(d)[ncol(d) - 1:0]
  d |>
    filter(.data[[id_col]] == "28" | str_detect(.data[[id_col]], "^28\\d{4}$")) |>
    transmute(fall, school = if_else(.data[[id_col]] == "28", "District Total", .data[[name_col]]),
              k12 = as.numeric(.data[[totals[1]]]), pk12 = as.numeric(.data[[totals[2]]]))
}

raw_path <- \(f) file.path(raw_dir, f)
enroll_raw <- bind_rows(
  read_enrollment_pdf(raw_path("school_enrollment_fy2017.pdf"), 2016),
  read_enrollment_pdf(raw_path("school_enrollment_fy2018.pdf"), 2017),
  read_counts_xlsx(raw_path("teacher_student_2018-19.xlsx"), 2018),
  read_counts_xlsx(raw_path("teacher_student_2019-20.xlsx"), 2019),
  map2(raw_path(sources$file[str_detect(sources$file, "^school_by_grade")]), grade_years, read_grade_xlsx) |>
    list_rbind()
)

# QA -----------------------------------------------------------------------------

# schools sum to the district total in every year
qa_sum <- enroll_raw |>
  group_by(fall) |>
  summarise(across(c(k12, pk12), \(x) sum(x[school != "District Total"]) - sum(x[school == "District Total"])))
stopifnot(all(qa_sum$k12 == 0), all(qa_sum$pk12 == 0), n_distinct(enroll_raw$fall) == 10)

# the 2020-21 counts file (same layout as 2018-19 and 2019-20) matches the
# by-grade file, so both come from the October 1 count
qa_2020 <- read_counts_xlsx(raw_path("teacher_student_2020-21.xlsx"), 2020) |>
  inner_join(filter(enroll_raw, fall == 2020), by = c("fall", "school"))
stopifnot(nrow(qa_2020) == sum(enroll_raw$fall == 2020), all(qa_2020$k12.x == qa_2020$k12.y))

# district ADM (fiscal year = spring year) vs October 1 K-12 enrollment
adm <- read_excel(raw_path("adm_history_district_fy1988_fy2026.xlsx"), skip = 1, .name_repair = "unique_quiet") |>
  filter(DISTRICT == "KODIAK") |>
  select(starts_with("FY")) |>
  pivot_longer(everything(), names_to = "fy", values_to = "adm", values_transform = as.numeric) |>
  transmute(fall = parse_number(fy) - 1, school = "District Total", adm)

adm_check <- enroll_raw |>
  filter(school == "District Total") |>
  left_join(adm, by = c("fall", "school")) |>
  mutate(pct_diff = 100 * (k12 - adm) / adm)
cat("Kodiak district: October 1 K-12 enrollment vs ADM\n")
print(adm_check |> select(fall, k12, adm, pct_diff) |> mutate(across(c(adm, pct_diff), \(x) round(x, 1))))

# 2025-26 ADM by school: "Foundation Formula, FY26 Budget Winter Revision with Hold Harmless",
# p. 2 of the winter revision. Correspondence is AKTEACH.
budget_names <- c("Akhiok" = "Akhiok School", "Chiniak" = "Chiniak School", "Port Lions" = "Port Lions School",
                  "Old Harbor" = "Old Harbor School", "Ouzinkie" = "Ouzinkie School",
                  "East" = "East Elementary", "Main" = "Main Elementary", "Peterson" = "Peterson Elementary",
                  "KMS" = "Kodiak Middle School", "KHS" = "Kodiak High School", "Correspondence" = "AKTEACH")
winter_lines <- unlist(str_split(suppressMessages(pdftools::pdf_text(winter_file))[2], "\n"))
m <- str_match(winter_lines, sprintf("^\\s*(%s)\\s+([\\d,]+\\.\\d{4})\\s",
                                     paste(names(budget_names), collapse = "|")))
m <- m[!is.na(m[, 1]), , drop = FALSE]
adm_fy26_school <- tibble(school = unname(budget_names[m[, 2]]), adm = parse_number(m[, 3]))
# one row per school, the same schools as the 2025-26 October 1 count, adding to DEED's FY26 ADM
stopifnot(nrow(adm_fy26_school) == length(budget_names),
          setequal(adm_fy26_school$school, setdiff(enroll_raw$school[enroll_raw$fall == 2025], "District Total")),
          isTRUE(all.equal(sum(adm_fy26_school$adm), adm$adm[adm$fall == 2025])))

# preliminary 2026-27 ADM by school: "District Foundation Summary", KIBSD 2026-27 Fall
# OASIS trial (10/27/2026, not certified), on p. 22 of the KIBSD Board Retreat packet,
# October 31, 2026. Elementary = PK-6, secondary = 7-12.
prelim_fall <- 2026
adm_prelim <- tribble(
  ~school,                ~elementary, ~secondary, ~adm,
  "Akhiok School",               6.50,       6.00,  12.50,
  "AKTEACH",                   148.85,     119.06, 267.91,
  "Chiniak School",             10.00,       8.00,  18.00,
  "East Elementary",           258.03,       0.00, 258.03,
  "Kodiak High School",          0.00,     479.09, 479.09,
  "Kodiak Middle School",      129.85,     265.50, 395.35,
  "Main Elementary",           180.20,       0.00, 180.20,
  "Old Harbor School",          24.40,       9.00,  33.40,
  "Ouzinkie School",             6.00,      10.00,  16.00,
  "Peterson Elementary",       175.25,       0.00, 175.25,
  "Port Lions School",          12.00,       9.00,  21.00
)
# rows add across and down to the printed totals, and every school is one we know
stopifnot(isTRUE(all.equal(adm_prelim$elementary + adm_prelim$secondary, adm_prelim$adm)),
          isTRUE(all.equal(colSums(adm_prelim[-1]), c(elementary = 951.08, secondary = 905.65, adm = 1856.73))),
          all(adm_prelim$school %in% enroll_raw$school[enroll_raw$fall == 2025]))
adm_fy26 <- adm$adm[adm$fall == prelim_fall - 1]
adm_fy27 <- sum(adm_prelim$adm)
cat(sprintf("\nDistrict ADM, FY26 to preliminary FY27: %.2f to %.2f (%+.2f%%)\n",
            adm_fy26, adm_fy27, 100 * (adm_fy27 / adm_fy26 - 1)))
adm_prelim <- adm_prelim |>
  select(school, adm) |>
  add_row(school = "District Total", adm = adm_fy27) |>
  mutate(fall = prelim_fall)

# tidy table -----------------------------------------------------------------------

town_buildings <- c("East Elementary", "Main Elementary", "North Star Elementary",
                    "Peterson Elementary", "Kodiak Middle School", "Kodiak High School")
homeschool <- "AKTEACH"

# adm: DEED's district ADM history for the district total; by school, KIBSD's budget
# documents for 2025-26 (final) and 2026-27 (preliminary). k12: October 1 enrollment,
# which has no 2026-27 count yet.
adm_all <- bind_rows(
  adm |> filter(fall %in% enroll_raw$fall) |> mutate(adm_source = "DEED district ADM history"),
  adm_fy26_school |> mutate(fall = prelim_fall - 1, adm_source = "KIBSD FY26 winter budget revision"),
  adm_prelim |> mutate(adm_source = "KIBSD Board Retreat packet, Oct 31 2026")
) |>
  mutate(adm_status = if_else(fall == prelim_fall, "preliminary", "final"))

enroll <- enroll_raw |>
  full_join(adm_all, by = c("fall", "school")) |>
  mutate(school_year = school_year(fall),
         group = case_when(school == "District Total" ~ "District total",
                           school %in% town_buildings ~ "Town school building",
                           school == homeschool ~ "Homeschool (AKTEACH)",
                           TRUE ~ "Rural school")) |>
  select(fall, school_year, school, group, k12, pk12, adm, adm_status, adm_source) |>
  arrange(fall, group, school)
stopifnot(!anyDuplicated(select(enroll, fall, school)))

write_csv(enroll, "data/processed/kibsd_enrollment_by_school.csv")

cat("\nOctober 1 K-12 enrollment by school:\n")
print(enroll |> filter(!is.na(k12)) |> select(school_year, school, k12) |>
        pivot_wider(names_from = school_year, values_from = k12), width = 220)
cat("\nADM by school (KIBSD budget documents; 2026-27 preliminary):\n")
print(enroll |> filter(fall >= prelim_fall - 1) |> select(school_year, school, adm) |>
        pivot_wider(names_from = school_year, values_from = adm))

# style (matches R/05) -----------------------------------------------------------------

surface <- "#fcfcfb"
ink <- "#0b0b0b"
ink2 <- "#52514e"
muted <- "#898781"
grid_col <- "#e1e0d9"
blue <- "#2a78d6"
orange <- "#eb6834"
font <- "Avenir Next"

theme_pub <- function(base = 11) {
  theme_minimal(base_size = base, base_family = font) +
    theme(
      plot.background = element_rect(fill = surface, colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = grid_col, linewidth = 0.3),
      panel.grid.major.x = element_blank(),
      axis.text = element_text(colour = muted),
      axis.title = element_text(colour = ink2),
      plot.title = element_text(colour = ink, face = "bold", size = rel(1.4)),
      plot.subtitle = element_text(colour = ink2, size = rel(1.0), margin = margin(2, 0, 6, 0)),
      plot.caption = element_text(colour = muted, hjust = 0, size = rel(0.72), lineheight = 1.15),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      strip.text = element_text(colour = ink, face = "bold", hjust = 0, size = rel(1.0)),
      legend.position = "none",
      plot.margin = margin(10, 14, 8, 10)
    )
}

save_png <- function(plot, path, width, height) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ragg::agg_png(path, width = width, height = height, units = "in", res = 300, background = surface)
  print(plot)
  invisible(dev.off())
}

years <- range(enroll$fall)
year_span <- paste(school_year(years[1]), "to", school_year(years[2]))
year_label <- \(x) if_else(x == prelim_fall, paste0(school_year(x), "\npreliminary"), school_year(x))
count_label <- \(x) scales::comma(x, accuracy = 1)
# caption paragraphs, each wrapped to the figure width (characters per line)
wrap_caption <- \(paragraphs, width) paste(str_wrap(paragraphs, width), collapse = "\n")

oct1_note <- sprintf(paste0(
  "Solid lines, filled circles: students in kindergarten through 12th grade on October 1 (preschool not ",
  "included), %s to %s. District-wide, October 1 enrollment was within %.0f%% of ADM each year."),
  school_year(years[1]), school_year(prelim_fall - 1), ceiling(max(abs(adm_check$pct_diff))))
adm_note <- sprintf(paste0(
  "Dashed lines, open circles: average daily membership (ADM) by school from KIBSD budget documents: %s ",
  "from the FY26 winter budget revision, and preliminary %s from KIBSD's fall %d count (preschool to 12th ",
  "grade, not yet certified by DEED). ADM by school for earlier years is not in the budget documents ",
  "KIBSD has posted online."),
  school_year(prelim_fall - 1), school_year(prelim_fall), prelim_fall)
source_note <- paste0(
  "Sources: Alaska Department of Education & Early Development, school enrollment and ADM reports; KIBSD ",
  "FY26 budget book (town and rural schools), FY26 winter budget revision (January 17, 2026) and Board ",
  "Retreat packet, October 31, 2026 (preliminary ADM).")

# sums by fall; NA where any school in the group lacks that measure
group_total <- function(d, ...) {
  d |>
    group_by(fall, ...) |>
    summarise(k12 = if (anyNA(k12)) NA_real_ else sum(k12),
              adm = if (anyNA(adm)) NA_real_ else sum(adm), .groups = "drop")
}

# one row per plotted point; measure is "k12" (October 1 enrollment) or "adm".
# Both are plotted for 2025-26, the year the two series overlap.
as_series <- function(d) {
  d |>
    pivot_longer(c(k12, adm), names_to = "measure", values_to = "students") |>
    filter(!is.na(students)) |>
    mutate(measure = factor(measure, levels = c("k12", "adm")))
}
measure_lines <- c(k12 = "solid", adm = "22")

# town total -------------------------------------------------------------------------------

town_total <- bind_rows(
  enroll |> filter(group == "Town school building") |> group_total() |>
    mutate(series = "Town school buildings"),
  enroll |> filter(group %in% c("Town school building", "Homeschool (AKTEACH)")) |> group_total() |>
    mutate(series = "Plus AKTEACH homeschool")
) |>
  as_series() |>
  mutate(series = fct_inorder(series))

ends <- town_total |>
  filter((fall == years[1] & measure == "k12") | fall == years[2])
buildings <- \(f, m) with(town_total, students[series == "Town school buildings" & fall == f & measure == m])

p_total <- ggplot(town_total, aes(fall, students, colour = series)) +
  geom_line(aes(linetype = measure, group = interaction(series, measure)), linewidth = 0.8) +
  geom_point(data = filter(town_total, measure == "k12"), aes(fill = series),
             size = 2.6, shape = 21, colour = surface, stroke = 0.6) +
  geom_point(data = filter(town_total, measure == "adm"), size = 2.3, shape = 21, fill = surface, stroke = 0.9) +
  geom_text(data = filter(ends, fall == years[1]), aes(label = count_label(students)),
            vjust = -1.1, family = font, size = 3.2, colour = ink2) +
  geom_text(data = filter(ends, fall == years[2]),
            aes(label = paste0(count_label(students), "  ", series)),
            hjust = 0, nudge_x = 0.18, family = font, size = 3.2, colour = ink2) +
  scale_colour_manual(values = c(blue, muted)) +
  scale_fill_manual(values = c(blue, muted)) +
  scale_linetype_manual(values = measure_lines) +
  scale_x_continuous(breaks = years[1]:years[2], labels = year_label,
                     expand = expansion(add = c(0.4, 4.3))) +
  scale_y_continuous(labels = scales::comma, breaks = scales::breaks_width(200)) +
  labs(
    title = paste("Kodiak town school enrollment,", year_span),
    subtitle = sprintf(paste0("October 1 enrollment in the town school buildings fell %.0f%% from %s to %s ",
                              "(%s to %s).\nADM fell another %.1f%% in %s (%s to %s, preliminary)."),
                       100 * (1 - buildings(prelim_fall - 1, "k12") / buildings(years[1], "k12")),
                       school_year(years[1]), school_year(prelim_fall - 1),
                       count_label(buildings(years[1], "k12")), count_label(buildings(prelim_fall - 1, "k12")),
                       100 * (1 - buildings(prelim_fall, "adm") / buildings(prelim_fall - 1, "adm")),
                       school_year(prelim_fall),
                       count_label(buildings(prelim_fall - 1, "adm")), count_label(buildings(prelim_fall, "adm"))),
    x = NULL, y = "Students",
    caption = wrap_caption(c(
      paste("Town school buildings: East, Main, North Star (closed after 2024–25), Peterson, Kodiak Middle",
            "and Kodiak High. AKTEACH is KIBSD's homeschool program."),
      oct1_note, adm_note, source_note), width = 160)
  ) +
  theme_pub()

save_png(p_total, "figs/kibsd_town_enrollment_total.png", width = 9, height = 5.8)

# by school: a town total panel, then one panel per school, each with its own vertical scale --

panel_names <- c("Total town schools" = "Total town schools",
                 "East Elementary" = "East (K–3 from 2025–26)",
                 "Main Elementary" = "Main (4–5 from 2025–26)",
                 "North Star Elementary" = "North Star (closed 2025)",
                 "Peterson Elementary" = "Peterson Elementary",
                 "Kodiak Middle School" = "Kodiak Middle School (6–8)",
                 "Kodiak High School" = "Kodiak High School (9–12)",
                 "AKTEACH" = "AKTEACH homeschool (K–12)")

# the total panel is the school buildings only; AKTEACH has its own panel
town_sum <- enroll |>
  filter(group == "Town school building") |>
  group_total() |>
  mutate(school = "Total town schools")

by_school <- enroll |>
  filter(group %in% c("Town school building", "Homeschool (AKTEACH)")) |>
  select(fall, school, k12, adm) |>
  bind_rows(town_sum) |>
  as_series() |>
  mutate(panel = factor(panel_names[school], levels = panel_names),
         col = if_else(school == homeschool, muted, blue))
stopifnot(!anyNA(by_school$panel))

# label each school's first point (October 1, 2016-17) and last point
school_ends <- by_school |>
  arrange(fall, measure) |>
  group_by(school) |>
  slice(c(1, n())) |>
  mutate(first = row_number() == 1, label_x = fall + if_else(first, -0.3, 0.3)) |>
  ungroup()

p_school <- ggplot(by_school, aes(fall, students)) +
  geom_line(aes(colour = col, linetype = measure), linewidth = 0.7) +
  geom_point(data = filter(by_school, measure == "k12"), aes(fill = col), size = 2.2, shape = 21,
             colour = surface, stroke = 0.5) +
  geom_point(data = filter(by_school, measure == "adm"), aes(colour = col), size = 2, shape = 21,
             fill = surface, stroke = 0.9) +
  geom_text(data = school_ends, aes(label_x, label = count_label(students), hjust = if_else(first, 1, 0)),
            family = font, size = 2.9, colour = ink2) +
  facet_wrap(~panel, ncol = 4, scales = "free_y") +
  scale_colour_identity() +
  scale_fill_identity() +
  scale_linetype_manual(values = measure_lines) +
  scale_x_continuous(breaks = c(2016, 2021, 2026), labels = year_label,
                     expand = expansion(add = c(2.1, 2.1))) +
  scale_y_continuous(labels = scales::comma, expand = expansion(mult = 0.12)) +
  labs(
    title = paste("Kodiak town school enrollment by school,", year_span),
    subtitle = sprintf(paste0("Students enrolled on October 1 each year, and average daily membership for %s and ",
                              "%s (preliminary); each panel has its own vertical scale"),
                       school_year(prelim_fall - 1), school_year(prelim_fall)),
    x = NULL, y = "Students",
    caption = wrap_caption(c(
      paste("Total town schools: East, Main, North Star, Peterson, Kodiak Middle and Kodiak High combined,",
            "not including AKTEACH. Elementary schools served kindergarten to 5th grade until North Star",
            "closed after 2024–25."),
      oct1_note, adm_note, source_note), width = 215)
  ) +
  theme_pub() +
  theme(panel.spacing.x = unit(1.4, "lines"), panel.spacing.y = unit(1.2, "lines"))

save_png(p_school, "figs/kibsd_town_enrollment_by_school.png", width = 12, height = 6.9)

# year-on-year change by group -----------------------------------------------------------------
# Each change compares two years on the same measure: ADM where both years have it (the
# district total every year; the school groups for 2026-27), otherwise October 1 enrollment.
# All four groups are printed; the figure shows the town buildings and the district total.

yoy_series <- c("Town school building" = "Town school buildings", "Rural school" = "Rural schools",
                "Homeschool (AKTEACH)" = "AKTEACH homeschool", "District total" = "District total")
yoy_cols <- c("Town school buildings" = blue, "District total" = ink)
signed_pct <- \(x, digits = 1) paste0(case_when(x > 0 ~ "+", x < 0 ~ "−", TRUE ~ ""),
                                      formatC(abs(x), format = "f", digits = digits), "%")

yoy <- enroll |>
  group_total(group) |>
  mutate(series = factor(yoy_series[group], levels = yoy_series)) |>
  arrange(series, fall) |>
  group_by(series) |>
  mutate(measure = if_else(!is.na(adm) & !is.na(lag(adm)), "adm", "k12"),
         pct = 100 * (if_else(measure == "adm", adm / lag(adm), k12 / lag(k12)) - 1)) |>
  ungroup() |>
  filter(fall > years[1])
stopifnot(!anyNA(yoy$pct), all(yoy$measure[yoy$fall == prelim_fall] == "adm"))

cat("\nChange from the year before (%), and the measure compared:\n")
print(yoy |> mutate(value = sprintf("%+.1f (%s)", pct, measure)) |> select(fall, series, value) |>
        pivot_wider(names_from = series, values_from = value), width = 200)

yoy_plot <- yoy |>
  filter(series %in% names(yoy_cols)) |>
  mutate(series = fct_drop(series))

# district ADM: fallen every year, and by more each year since run_from
district <- filter(yoy_plot, series == "District total")
stopifnot(all(district$pct < 0), all(district$measure == "adm"))
run_from <- district$fall[max(which(c(TRUE, diff(district$pct) >= 0)))]
# the town buildings fell faster than the district in each of the last n_faster years
faster <- yoy_plot |>
  select(fall, series, pct) |>
  pivot_wider(names_from = series, values_from = pct) |>
  arrange(fall) |>
  mutate(faster = `Town school buildings` < `District total`)
n_faster <- match(FALSE, rev(faster$faster)) - 1

p_yoy <- ggplot(yoy_plot, aes(fall, pct, colour = series)) +
  geom_hline(yintercept = 0, colour = ink2, linewidth = 0.4) +
  geom_line(data = filter(yoy_plot, fall < prelim_fall), linewidth = 0.8) +
  geom_line(data = filter(yoy_plot, fall >= prelim_fall - 1), linewidth = 0.8, linetype = "22") +
  geom_point(aes(fill = series), size = 2.6, shape = 21, colour = surface, stroke = 0.5) +
  ggrepel::geom_text_repel(data = filter(yoy_plot, fall == prelim_fall),
                           aes(label = paste0(signed_pct(pct), "  ", series)),
                           hjust = 0, direction = "y", nudge_x = 0.2, xlim = c(prelim_fall + 0.15, NA),
                           box.padding = 0.12, min.segment.length = Inf, seed = 1,
                           family = font, size = 3.2, colour = ink2) +
  scale_colour_manual(values = yoy_cols) +
  scale_fill_manual(values = yoy_cols) +
  scale_x_continuous(breaks = (years[1] + 1):years[2], labels = year_label,
                     expand = expansion(add = c(0.4, 2.4))) +
  scale_y_continuous(labels = \(x) signed_pct(x, 0), breaks = scales::breaks_width(2)) +
  labs(
    title = paste("Kodiak school enrollment: change from the year before,", school_year(years[1] + 1),
                  "to", school_year(years[2])),
    subtitle = sprintf(paste0("District ADM has fallen every year since %s, and the drop has grown each year ",
                              "since %s (%s to %s).\nThe town school buildings fell faster than the district ",
                              "in each of the last %s years."),
                       school_year(years[1]), school_year(run_from),
                       signed_pct(district$pct[district$fall == run_from]),
                       signed_pct(district$pct[district$fall == prelim_fall]),
                       c("one", "two", "three", "four", "five", "six", "seven", "eight", "nine")[n_faster]),
    x = NULL, y = "Change from the year before",
    caption = wrap_caption(c(
      paste("Each point compares a school year with the year before, on the same measure for both years.",
            "District total: average daily membership (ADM) from DEED, and preliminary ADM for",
            sprintf("%s from KIBSD's fall %d count.", school_year(prelim_fall), prelim_fall)),
      sprintf(paste("Town school buildings (East, Main, North Star until it closed after 2024–25, Peterson,",
                    "Kodiak Middle and Kodiak High; not including AKTEACH homeschool): October 1 enrollment,",
                    "kindergarten to 12th grade, to %s. For %s (dashed), preliminary ADM by school is compared",
                    "with %s ADM by school from KIBSD's FY26 winter budget revision; ADM by school for earlier",
                    "years is not in the budget documents KIBSD has posted online."),
              school_year(prelim_fall - 1), school_year(prelim_fall), school_year(prelim_fall - 1)),
      source_note), width = 172)
  ) +
  theme_pub()

save_png(p_yoy, "figs/kibsd_enrollment_yoy_change.png", width = 10, height = 6)
