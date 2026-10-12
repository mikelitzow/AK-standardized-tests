# Compare Kodiak with other Alaska school districts: % proficient or advanced
# on AK STAR (ELA, math) and the Alaska Science Assessment against the child
# poverty rate, with the district as the unit.
#
# - y: % proficient or advanced, pooled over AK STAR grades 3-9, spring
#   2023-2026, and science grades 5, 8, 10, spring 2022-2026
#   (DEED publishes no district scale scores, so this is the only score)
# - x: SAIPE child poverty rate (ages 5-17), income years 2022-2024 pooled
# - fit: least squares, each district counted once; the six districts with
#   mostly non-local (correspondence) enrollment are left out of the main fit
#
# Inputs: data/processed/akstar_grade.csv, science_grade.csv, district_indicators.csv
# Outputs: figs/kodiak_vs_districts_poverty.png
#          figs/kodiak_vs_districts_poverty_grades_8_9.png
#          figs/kodiak_vs_districts_poverty_science.png
#          figs/diagnostics/kodiak_residuals_by_year_grade.png
#          figs/diagnostics/correspondence_sensitivity.png
#          data/processed/district_prof_poverty.csv
#          data/processed/kodiak_fit_summary.csv
# Run from the project root.

library(tidyverse)
library(ggrepel)
library(patchwork)

akstar_grade <- read_csv("data/processed/akstar_grade.csv", show_col_types = FALSE)
science_grade <- read_csv("data/processed/science_grade.csv", show_col_types = FALSE)
results <- bind_rows(akstar_grade, science_grade)
indicators <- read_csv("data/processed/district_indicators.csv", show_col_types = FALSE)

kodiak <- "Kodiak"
subject_labels <- c(ELA = "English language arts", Math = "Math", Science = "Science")

short_name <- function(x) {
  x |>
    str_remove(" (City |Borough |Area |Public )?(School District|Schools)$") |>
    str_remove(" (Borough|City|Island Borough|Gateway Borough)$") |>
    recode("Matanuska-Susitna" = "Mat-Su", "Fairbanks North Star" = "Fairbanks",
           "Northwest Arctic" = "NW Arctic", "Kodiak Island" = "Kodiak",
           "Ketchikan Gateway" = "Ketchikan", "Saint Mary's" = "St. Mary's")
}

districts <- indicators |>
  filter(!is.na(child_poverty_pct_2022_24)) |>
  transmute(district_id, district = short_name(district_name),
            pov = child_poverty_pct_2022_24, enrollment = enrollment_3_9_mean,
            nonlocal = nonlocal_enrollment)

# pooled % proficient: suppressed rows (<5 tested) drop out; rows reported as a
# range ("5% or fewer") enter at the midpoint of the range
pool_prof <- function(d, ...) {
  d |>
    filter(level == "District", !suppressed) |>
    mutate(pct = coalesce(prof_pct, (prof_pct_min + prof_pct_max) / 2)) |>
    group_by(district_id, subject, ...) |>
    summarise(prof = sum(pct * tested) / sum(tested), tested = sum(tested),
              any_range = any(pct_is_range), .groups = "drop") |>
    inner_join(districts, by = "district_id")
}

all_grades <- results |> filter(grade == "All") |> pool_prof()

# mean annual enrollment by district for each subject (and grade), for bubble size
mean_enrollment <- function(d, ...) {
  d |>
    filter(level == "District") |>
    group_by(district_id, subject, ...) |>
    summarise(enrollment = mean(enrollment), .groups = "drop")
}

# fits ---------------------------------------------------------------------------

kodiak_fit <- function(d, model = c("lm", "weighted", "logit")) {
  model <- match.arg(model)
  m <- switch(model,
    lm = lm(prof ~ pov, d),
    weighted = lm(prof ~ pov, d, weights = tested),
    logit = glm(prof / 100 ~ pov, family = quasibinomial, data = d)
  )
  fitted_pct <- if (model == "logit") 100 * fitted(m) else fitted(m)
  resid_pct <- d$prof - fitted_pct
  k <- d$district == kodiak
  out <- tibble(
    n = nrow(d), slope = if (model == "lm") coef(m)[["pov"]] else NA_real_,
    r2 = if (model == "lm") summary(m)$r.squared else NA_real_,
    p = if (model == "lm") summary(m)$coefficients["pov", 4] else NA_real_,
    kodiak_obs = d$prof[k], kodiak_expected = fitted_pct[k], kodiak_resid = resid_pct[k],
    # share of districts whose residual is at or below Kodiak's
    kodiak_resid_pctile = mean(resid_pct <= resid_pct[k])
  )
  if (model == "lm") {
    pi <- predict(m, d[k, ], interval = "prediction")
    out <- mutate(out, kodiak_pi_lo = pi[, "lwr"], kodiak_pi_hi = pi[, "upr"])
  }
  out
}

fit_summary <- bind_rows(
  all_grades |> filter(!nonlocal) |> group_by(subject) |>
    group_modify(\(d, k) kodiak_fit(d, "lm")) |> mutate(fit = "main: excl. non-local"),
  all_grades |> group_by(subject) |>
    group_modify(\(d, k) kodiak_fit(d, "lm")) |> mutate(fit = "all districts"),
  all_grades |> filter(!nonlocal) |> group_by(subject) |>
    group_modify(\(d, k) kodiak_fit(d, "weighted")) |> mutate(fit = "weighted by students tested"),
  all_grades |> filter(!nonlocal) |> group_by(subject) |>
    group_modify(\(d, k) kodiak_fit(d, "logit")) |> mutate(fit = "logit (quasibinomial)")
) |>
  ungroup() |>
  relocate(fit, .after = subject)

by_year <- results |> filter(grade == "All") |> pool_prof(year) |>
  filter(!nonlocal) |> group_by(subject, year) |>
  group_modify(\(d, k) kodiak_fit(d, "lm")) |> ungroup()

by_grade <- results |> filter(grade != "All") |> pool_prof(grade) |>
  filter(!nonlocal) |> group_by(subject, grade) |>
  group_modify(\(d, k) kodiak_fit(d, "lm")) |> ungroup()

main <- filter(fit_summary, fit == "main: excl. non-local")
main_models <- all_grades |>
  filter(!nonlocal) |>
  split(~subject) |>
  map(\(d) lm(prof ~ pov, d))
predict_main <- function(subject, pov) {
  map2_dbl(subject, pov, \(s, x) predict(main_models[[s]], tibble(pov = x)))
}

district_out <- all_grades |>
  mutate(expected = if_else(nonlocal, NA_real_, predict_main(subject, pov)),
         resid = prof - expected) |>
  select(subject, district_id, district, pov, enrollment, tested, prof, any_range,
         nonlocal, expected, resid)

write_csv(district_out, "data/processed/district_prof_poverty.csv")
write_csv(bind_rows(fit_summary |> mutate(level = "all grades pooled"),
                    by_year |> mutate(level = paste("year", year)) |> select(-year),
                    by_grade |> mutate(level = paste("grade", grade)) |> select(-grade)),
          "data/processed/kodiak_fit_summary.csv")

cat("Fits, all grades pooled (AK STAR 2023-2026, science 2022-2026):\n")
print(fit_summary |> mutate(across(where(is.double), \(x) signif(x, 3))), width = 200)
cat("\nKodiak residual by year:\n")
print(by_year |> select(subject, year, kodiak_obs, kodiak_expected, kodiak_resid, kodiak_resid_pctile) |>
        mutate(across(where(is.double), \(x) round(x, 1))))
cat("\nKodiak residual by grade:\n")
print(by_grade |> select(subject, grade, n, kodiak_obs, kodiak_expected, kodiak_resid, kodiak_resid_pctile) |>
        mutate(across(where(is.double), \(x) round(x, 2))), n = 30)

# style --------------------------------------------------------------------------

surface <- "#fcfcfb"
ink <- "#0b0b0b"
ink2 <- "#52514e"
muted <- "#898781"
grid_col <- "#e1e0d9"
blue <- "#2a78d6"
orange <- "#eb6834"
aqua <- "#1baf7a"
font <- "Avenir Next"

theme_pub <- function(base = 11) {
  theme_minimal(base_size = base, base_family = font) +
    theme(
      plot.background = element_rect(fill = surface, colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = grid_col, linewidth = 0.3),
      axis.text = element_text(colour = muted),
      axis.title = element_text(colour = ink2),
      plot.title = element_text(colour = ink, face = "bold", size = rel(1.4)),
      plot.subtitle = element_text(colour = ink2, size = rel(1.0), margin = margin(2, 0, 6, 0)),
      plot.caption = element_text(colour = muted, hjust = 0, size = rel(0.72), lineheight = 1.15),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      strip.text = element_text(colour = ink, face = "bold", hjust = 0, size = rel(1.1)),
      legend.title = element_text(colour = ink2, size = rel(0.85)),
      legend.text = element_text(colour = ink2, size = rel(0.85)),
      plot.margin = margin(10, 14, 8, 10)
    )
}

save_png <- function(plot, path, width, height) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ragg::agg_png(path, width = width, height = height, units = "in", res = 300, background = surface)
  print(plot)
  invisible(dev.off())
}

fmt_p <- function(p) if_else(p < 0.001, "p < 0.001", sprintf("p = %.3f", p))

# poverty-fit figure ----------------------------------------------------------------

# Kodiak's peers: similar child poverty, above expected in all 13 subject-years
# (ELA and math 2023-2026, science 2022-2026; see R/06)
label_set <- c("Sitka", "Petersburg", "Cordova", "Kenai Peninsula")
# quieter reference labels spread across the poverty range
anchor_set <- c("Anchorage", "North Slope", "Nome", "Lower Kuskokwim", "Yupiit")

source_note <- function(test = "AK STAR") paste0(
  "Labeled for comparison: Sitka, Petersburg, Cordova and Kenai Peninsula, districts with child poverty similar to Kodiak's ",
  "that scored above expected in English, math and science every year.\nGrey labels mark other districts across the poverty range.\n",
  "Not shown: six districts whose statewide correspondence programs enroll mostly students who live elsewhere ",
  "(Galena, Nenana, Yukon-Koyukuk, Chugach, Denali, Craig), and Mt. Edgecumbe (state boarding school).\n",
  "Districts reported only as “5% or fewer” proficient are plotted at the midpoint of that range.\n",
  "Sources: Alaska Department of Education & Early Development, ", test, " results; ",
  "U.S. Census Bureau, SAIPE school district estimates 2022–2024."
)

# Bubble plot of % proficient against child poverty with a least-squares line
# fit separately in each panel (each district counted once), Kodiak's
# observed-to-expected bar, and a Kodiak callout in the upper middle.
# d needs: panel (factor), district, pov, prof, enrollment
poverty_fit_plot <- function(d, size_name, size_breaks, free_y = FALSE, ncol = 2,
                             max_size = 13) {
  nested <- d |>
    nest(.by = panel) |>
    mutate(model = map(data, \(x) lm(prof ~ pov, x)))

  line_d <- nested |>
    mutate(line = map2(data, model, \(x, m) {
      xs <- seq(min(x$pov), max(x$pov), length.out = 50)
      tibble(x = xs, y = predict(m, tibble(pov = xs)))
    })) |>
    select(panel, line) |>
    unnest(line)

  stats_d <- nested |>
    transmute(panel,
              text = sprintf("R² = %.2f  ·  %s  ·  %d districts",
                             map_dbl(model, \(m) summary(m)$r.squared),
                             fmt_p(map_dbl(model, \(m) summary(m)$coefficients["pov", 4])),
                             map_int(data, nrow)))

  # large bubbles first so small districts draw on top
  pts <- nested |>
    mutate(data = map2(data, model, \(x, m) mutate(x, expected = fitted(m), resid = resid(m)))) |>
    select(panel, data) |>
    unnest(data) |>
    mutate(is_kodiak = district == kodiak) |>
    arrange(desc(enrollment))

  y_top <- pts |>
    group_by(panel) |>
    summarise(y_top = max(prof)) |>
    mutate(y_top = if (free_y) y_top else max(y_top))

  k_d <- pts |>
    filter(is_kodiak) |>
    left_join(y_top, by = "panel") |>
    mutate(text = sprintf("Kodiak: %.1f%%\n%.1f points %s expected (%.1f%%)",
                          prof, abs(resid), if_else(resid < 0, "below", "above"), expected),
           label_x = 13.5, label_y = 0.9 * y_top)

  # every point, Kodiak's observed-to-expected bar, its callout line and the
  # fit line go to the repel layer so labels avoid them all; only label_set
  # districts get visible text
  label_d <- bind_rows(
    pts |> transmute(panel, pov, prof,
                     label = if_else(district %in% c(label_set, anchor_set), district, "")),
    k_d |> reframe(pov, prof = seq(prof, expected, length.out = 6), label = "", .by = panel),
    k_d |> reframe(pov = seq(pov, label_x - 0.4, length.out = 15),
                   prof = seq(prof, label_y - 0.025 * y_top, length.out = 15), label = "",
                   .by = panel),
    line_d |> transmute(panel, pov = x, prof = y, label = "")
  ) |>
    # the three small peers sit within half a point of poverty of each other:
    # stack their labels to the left of the cluster; Kenai's label goes right
    mutate(nudge = case_when(label == "Kenai Peninsula" ~ 3, label %in% label_set ~ -2.5,
                             label == "Anchorage" ~ 1.5, TRUE ~ 0),
           # Anchorage sits under the big low-poverty bubbles; send its label below them
           nudge_y = if_else(label == "Anchorage", -0.12 * max(prof), 0),
           col = if_else(label %in% label_set, ink2, muted),
           hj = if_else(nudge < 0, 1, 0))

  ggplot(pts, aes(pov, prof)) +
    geom_line(data = line_d, aes(x, y), colour = ink2, linewidth = 0.6) +
    geom_point(data = filter(pts, !is_kodiak, !district %in% label_set), aes(size = enrollment),
               shape = 21, fill = blue, colour = surface, alpha = 0.55, stroke = 0.5) +
    # labeled peers drawn opaque so each label finds its bubble
    geom_point(data = filter(pts, district %in% label_set), aes(size = enrollment),
               shape = 21, fill = blue, colour = surface, stroke = 0.6) +
    geom_segment(data = k_d, aes(xend = pov, yend = expected), colour = orange, linewidth = 0.9) +
    geom_point(data = k_d, aes(y = expected), shape = 21, size = 2.2, fill = surface,
               colour = orange, stroke = 0.9) +
    geom_point(data = k_d, aes(size = enrollment), shape = 21, fill = orange,
               colour = surface, stroke = 0.6) +
    geom_text_repel(data = label_d, aes(label = label, hjust = hj, colour = col),
                    nudge_x = label_d$nudge, nudge_y = label_d$nudge_y, direction = "y",
                    family = font, size = 2.9, segment.colour = muted,
                    segment.size = 0.25, min.segment.length = 0, box.padding = 0.3,
                    point.padding = 0.2, seed = 3, max.overlaps = Inf) +
    scale_colour_identity() +
    geom_segment(data = k_d, aes(xend = label_x - 0.4, yend = label_y - 0.025 * y_top),
                 colour = orange, linewidth = 0.35) +
    geom_text(data = k_d, aes(label_x, label_y, label = text), family = font, size = 3.2,
              colour = ink, fontface = "bold", hjust = 0, vjust = 0.5, lineheight = 1.05) +
    geom_text(data = stats_d, aes(x = max(pts$pov), y = Inf, label = text), inherit.aes = FALSE,
              hjust = 1, vjust = 1.6, family = font, size = 2.8, colour = muted) +
    facet_wrap(~panel, ncol = ncol, scales = if (free_y) "free_y" else "fixed") +
    scale_size_area(max_size = max_size, breaks = size_breaks, labels = scales::comma,
                    name = size_name) +
    scale_x_continuous(labels = \(x) paste0(x, "%"), breaks = seq(0, 40, 10)) +
    scale_y_continuous(labels = \(x) paste0(x, "%")) +
    coord_cartesian(ylim = c(0, NA)) +
    labs(x = "Children ages 5–17 living in poverty", y = "Proficient or advanced") +
    theme_pub() +
    theme(legend.position = "top", legend.justification = "left",
          legend.margin = margin(0, 0, 0, 0), legend.box.margin = margin(-4, 0, -10, -6),
          panel.spacing.x = unit(1.6, "lines"), panel.spacing.y = unit(1.2, "lines")) +
    guides(size = guide_legend(override.aes = list(fill = blue, alpha = 0.55)))
}

# main figure: all grades ------------------------------------------------------------------

p_main <- district_out |>
  filter(!nonlocal, subject %in% c("ELA", "Math")) |>
  mutate(panel = factor(subject_labels[subject], levels = subject_labels)) |>
  poverty_fit_plot(size_name = "Students enrolled in grades 3–9",
                   size_breaks = c(100, 1000, 10000), ncol = 2) +
  labs(
    title = "Kodiak scores about as expected in English, below expected in math",
    subtitle = paste0("Share of students proficient or advanced on AK STAR (grades 3–9, 2023–2026 combined) ",
                      "vs. child poverty rate, by Alaska school district"),
    caption = paste0(
      "Each bubble is a school district; the line is a least-squares fit with each district counted once. ",
      "The orange bar runs from Kodiak's score to the score expected for its poverty rate.\n",
      source_note()
    )
  )

save_png(p_main, "figs/kodiak_vs_districts_poverty.png", width = 12, height = 7)

# grades 8 and 9: separate fit for each grade and subject -----------------------------------

grade_89 <- akstar_grade |>
  filter(grade %in% c("8", "9")) |>
  pool_prof(grade) |>
  filter(!nonlocal) |>
  select(-enrollment) |>
  left_join(mean_enrollment(akstar_grade, grade), by = c("district_id", "subject", "grade")) |>
  mutate(panel = factor(paste0(grade, "th grade · ", subject_labels[subject]),
                        levels = paste0(rep(c(8, 9), each = 2), "th grade · ",
                                        subject_labels[c("ELA", "Math")])))

stopifnot(!anyNA(grade_89$panel))

p_89 <- grade_89 |>
  poverty_fit_plot(size_name = "Students enrolled in the grade (average per year)",
                   size_breaks = c(30, 300, 3000), free_y = TRUE, ncol = 2, max_size = 12) +
  labs(
    title = "Kodiak falls further below expected in 9th grade, especially in math",
    subtitle = paste0("Share of 8th and 9th graders proficient or advanced on AK STAR (2023–2026 combined) ",
                      "vs. child poverty rate, by Alaska school district"),
    caption = paste0(
      "Each bubble is a school district; each panel has its own least-squares fit with each district counted once, ",
      "and its own vertical scale.\nThe orange bar runs from Kodiak's score to the score expected for its poverty rate.\n",
      source_note()
    )
  )

save_png(p_89, "figs/kodiak_vs_districts_poverty_grades_8_9.png", width = 12, height = 11)

# science: all tested grades and each grade, separate fit per panel --------------------------

science_panels <- c(All = "All tested grades (5, 8, 10)", "5" = "5th grade",
                    "8" = "8th grade", "10" = "10th grade")

science_d <- science_grade |>
  pool_prof(grade) |>
  filter(!nonlocal) |>
  select(-enrollment) |>
  left_join(mean_enrollment(science_grade, grade), by = c("district_id", "subject", "grade")) |>
  mutate(panel = factor(science_panels[grade], levels = science_panels))

# headline written after reviewing the fits (see docs/analysis_log.md)
science_title <- "In science, Kodiak trails the score expected for its poverty rate, most in 10th grade"

stopifnot(!anyNA(science_d$panel))

p_science <- science_d |>
  poverty_fit_plot(size_name = "Students enrolled in the grade(s) (average per year)",
                   size_breaks = c(30, 300, 3000), free_y = TRUE, ncol = 2, max_size = 12) +
  labs(
    title = science_title,
    subtitle = paste0("Share of students proficient or advanced on the Alaska Science Assessment ",
                      "(2022\u20132026 combined) vs. child poverty rate, by Alaska school district"),
    caption = paste0(
      "Each bubble is a school district; each panel has its own least-squares fit with each district counted once, ",
      "and its own vertical scale.\nThe orange bar runs from Kodiak's score to the score expected for its poverty rate. ",
      "Science is tested in grades 5, 8 and 10 only.\n",
      source_note("Alaska Science Assessment")
    )
  )

save_png(p_science, "figs/kodiak_vs_districts_poverty_science.png", width = 12, height = 11)

# Kodiak variability: residual by year and by grade ------------------------------------

resid_theme <- theme_pub(10) +
  theme(legend.position = "none", plot.title = element_text(size = rel(1.15)))
subj_cols <- c(ELA = blue, Math = orange, Science = aqua)
short_subject <- c(ELA = "English", Math = "Math", Science = "Science")
signed <- function(x) case_when(x > 0 ~ paste0("+", x), x < 0 ~ paste0("\u2212", abs(x)), TRUE ~ "0")

end_labels <- function(d, x) {
  d |> group_by(subject) |> filter({{ x }} == max({{ x }})) |> ungroup()
}

p_year <- ggplot(by_year, aes(year, kodiak_resid, colour = subject)) +
  geom_hline(yintercept = 0, colour = ink2, linewidth = 0.4) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.6, shape = 21, fill = NA, stroke = 0) +
  geom_point(aes(fill = subject), size = 2.6, shape = 21, colour = surface, stroke = 0.6) +
  geom_text(data = end_labels(by_year, year), aes(label = short_subject[subject]),
            hjust = 0, nudge_x = 0.12, family = font, size = 3, colour = ink2) +
  scale_colour_manual(values = subj_cols) +
  scale_fill_manual(values = subj_cols) +
  scale_x_continuous(breaks = 2022:2026, expand = expansion(add = c(0.15, 1.1))) +
  scale_y_continuous(labels = signed) +
  labs(title = "By year (all grades)", x = NULL,
       y = "Points above or below expected") +
  resid_theme

grade_d <- by_grade |> mutate(grade = as.integer(grade))
p_grade <- ggplot(grade_d, aes(grade, kodiak_resid, colour = subject)) +
  geom_hline(yintercept = 0, colour = ink2, linewidth = 0.4) +
  geom_line(linewidth = 0.7) +
  geom_point(aes(fill = subject), size = 2.6, shape = 21, colour = surface, stroke = 0.6) +
  geom_text(data = end_labels(grade_d, grade), aes(label = short_subject[subject]),
            hjust = 0, nudge_x = 0.15, family = font, size = 3, colour = ink2) +
  scale_colour_manual(values = subj_cols) +
  scale_fill_manual(values = subj_cols) +
  scale_x_continuous(breaks = 3:10, labels = \(x) paste("Gr.", x), expand = expansion(add = c(0.2, 1.6))) +
  scale_y_continuous(labels = signed) +
  labs(title = "By grade (all years combined)", x = NULL, y = NULL) +
  resid_theme

kodiak_part <- akstar_grade |>
  filter(district_id == districts$district_id[districts$district == kodiak], grade == "All",
         subject == "ELA") |>
  arrange(year) |>
  with(paste0(paste0(round(participation_pct), "% in ", year), collapse = ", ")) |>
  paste0(".")

p_var <- (p_year | p_grade) +
  plot_annotation(
    title = "Kodiak vs. the score expected for its child poverty rate",
    subtitle = "Same district-level fit as the main figure, refit for each year and each grade",
    caption = paste0("Kodiak participation (share of enrolled students tested, ELA): ", kodiak_part, "\n",
                     "English and math: AK STAR 2023\u20132026; science: Alaska Science Assessment 2022\u20132026 (grades 5, 8, 10).\n",
                     "Sources: Alaska DEED assessment results; U.S. Census Bureau SAIPE 2022\u20132024."),
    theme = theme_pub(10)
  )

save_png(p_var, "figs/diagnostics/kodiak_residuals_by_year_grade.png", width = 11, height = 4.8)

# sensitivity: with and without non-local (correspondence) districts --------------------

sens_lines <- bind_rows(
  all_grades |> filter(!nonlocal) |> mutate(fit = "Fit without them (main)"),
  all_grades |> mutate(fit = "Fit with them")
) |>
  group_by(subject, fit) |>
  group_modify(\(d, k) {
    m <- lm(prof ~ pov, d)
    x <- seq(min(d$pov), max(d$pov), length.out = 50)
    tibble(x = x, y = predict(m, tibble(pov = x)))
  }) |>
  ungroup() |>
  mutate(panel = factor(subject_labels[subject], levels = subject_labels))

sens_pts <- all_grades |>
  mutate(panel = factor(subject_labels[subject], levels = subject_labels),
         group = if_else(nonlocal, "Mostly non-local enrollment", "Other districts"))

p_sens <- ggplot(sens_pts, aes(pov, prof)) +
  geom_line(data = sens_lines, aes(x, y, colour = fit), linewidth = 0.7) +
  geom_point(aes(size = enrollment, fill = group), shape = 21, colour = surface,
             stroke = 0.5, alpha = 0.7) +
  geom_text_repel(data = filter(sens_pts, nonlocal), aes(label = district), family = font,
                  size = 2.8, colour = ink2, segment.colour = muted, segment.size = 0.25,
                  seed = 2) +
  facet_wrap(~panel, nrow = 1) +
  scale_colour_manual(values = c("Fit without them (main)" = ink2, "Fit with them" = orange),
                      name = NULL) +
  scale_fill_manual(values = c("Other districts" = blue, "Mostly non-local enrollment" = orange),
                    name = NULL) +
  scale_size_area(max_size = 12, guide = "none") +
  scale_x_continuous(labels = \(x) paste0(x, "%")) +
  scale_y_continuous(labels = \(x) paste0(x, "%")) +
  coord_cartesian(ylim = c(0, NA)) +
  labs(title = "Including the six correspondence-dominated districts barely changes the fit",
       x = "Children ages 5–17 living in poverty", y = "Proficient or advanced") +
  theme_pub(10) +
  theme(legend.position = "top", legend.justification = "left") +
  guides(fill = guide_legend(override.aes = list(size = 4)))

save_png(p_sens, "figs/diagnostics/correspondence_sensitivity.png", width = 14, height = 5)
