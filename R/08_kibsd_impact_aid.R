# Kodiak Island Borough School District (KIBSD) federal impact aid: what arrived each
# fiscal year, what was held over as committed fund balance on June 30, and what the
# next year's budget counted as revenue.
#
# Question (prompt "Tracking federal aid in the budget", 2026-11-05): is impact aid a
# spending buffer for FY28, or does each year's payment simply fund the next budget?
#
# Impact aid here is the four General Fund revenue lines: impact aid military, impact
# aid military special education, Department of Defense, and direct impact aid.
# Impact aid construction (a separate capital project fund) is left out.
#
# Sources (kibsd.org, downloaded to data/raw/kibsd_finance/):
#   Audited financial statements FY21-FY25:
#     General Fund budget and actual schedule (exhibit G-2): final budget and actual
#     General Fund balance sheet: fund balance committed to "Impact Aid" on June 30
#     Schedule of expenditures of federal awards: impact aid by entitlement year
#   FY26 Budget Book (adopted June 16, 2025) and FY26 winter revisions (January 2026)
#   FY28 projected revenue scenarios (January 2026)
#   FY27 approved budget: KIBSD Board Retreat packet, October 31, 2026, p. 21 (an image
#     table, typed in below)
#
# Outputs: data/processed/kibsd_impact_aid.csv
#          figs/kibsd_impact_aid_carryover.png
# Run from the project root.

library(tidyverse)
library(httr2)

raw_dir <- "data/raw/kibsd_finance"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
ua <- "R httr2 (AK-standardized-tests public data project)"
fy_label <- \(fy) sprintf("FY%02d", fy %% 100)

# downloads ----------------------------------------------------------------------

sources <- tribble(
  ~fy,  ~doc,               ~path,
  2021, "audit",            "2023/03/KIBSD-Final-FS-2021.pdf",
  2022, "audit",            "2023/03/KIBSD-Final-FS-2022.pdf",
  2023, "audit",            "2024/02/KIBSD-Final-FS-2023.pdf",
  2024, "audit",            "2025/01/KIBSD-Final-FS-2024.pdf",
  2025, "audit",            "2025/12/FY25-Financial-Statement.pdf",
  2026, "adopted",          "2025/10/KIBSD-FY26-Budget-Book.pdf",
  2026, "winter revision",  "2026/01/WINTER-REVISIONS-REVENUE-3-PAGE.pdf",
  2028, "projection",       "2026/01/FY28-PROJECTED-REVENUE-AT-3percent-W.-HH-AND-INF-SCENARIOS.pdf"
) |>
  mutate(file = file.path(raw_dir, basename(path)))

fetch <- function(path, file) {
  if (!file.exists(file)) {
    request(paste0("https://www.kibsd.org/wp-content/uploads/", path)) |>
      req_user_agent(ua) |>
      req_perform(path = file)
    Sys.sleep(1)
  }
}
walk2(sources$path, sources$file, fetch)

read_lines_pdf <- function(file) unlist(str_split(suppressMessages(pdftools::pdf_text(file)), "\n"))

# "(23,883)" is negative and "-" is zero
num <- function(x) {
  x <- str_trim(x)
  parse_number(str_replace(x, "^-$", "0")) * if_else(str_detect(x, "^\\("), -1, 1)
}

# audits ---------------------------------------------------------------------------

items <- c(military = "Impact aid military", sped = "Impact aid military – special education",
           dod = "Department of Defense", direct = "Federal direct sources - Impact aid")
token <- "(?:\\(?[\\d,]+\\)?|-)"

# exhibit G-2 rows have four amounts: final budget, actual, variance, prior-year actual
read_budget_actual <- function(lines, fy) {
  imap(items, function(label, item) {
    hit <- str_match(lines, paste0("^\\s*", label, "\\s+((?:", token, "\\s+){3}", token, ")\\s*$"))
    hit <- hit[!is.na(hit[, 1]), 2]
    stopifnot(length(hit) == 1)
    x <- num(str_split_1(str_squish(hit), " "))
    tibble(fy, item, budget = x[1], actual = x[2])
  }) |>
    list_rbind()
}

# General Fund balance sheet: committed "Impact Aid", this June 30 and last
read_committed <- function(lines, fy) {
  hit <- str_match(lines, regex("^\\s*Impact Aid\\s+([\\d,]+)\\s+([\\d,]+)\\s*$", ignore_case = TRUE))
  hit <- hit[!is.na(hit[, 1]), , drop = FALSE]
  stopifnot(nrow(hit) == 1)
  tibble(fy = c(fy, fy - 1), committed = parse_number(hit[1, 2:3]))
}

# federal awards schedule: impact aid by entitlement year (11-AK-yyyy-...); Defense
# money has no award number. The second amount (expenditures) is what the General
# Fund books as revenue.
read_awards <- function(lines, fy) {
  hit <- str_match(lines, paste0("^\\s*(\\S.*?)\\s+84\\.041\\s+(11-AK-(\\d{4})-\\d{4}|None)",
                                 "\\s+\\$?\\s*([\\d,]+)\\s+([\\d,]+)\\s*$"))
  hit <- hit[!is.na(hit[, 1]) & !str_detect(hit[, 2], regex("construction|^total", ignore_case = TRUE)), ,
             drop = FALSE]
  tibble(fy, entitlement_year = as.numeric(hit[, 4]), amount = parse_number(hit[, 6])) |>
    mutate(part = case_when(is.na(entitlement_year) ~ "Department of Defense",
                            entitlement_year == fy ~ "This year's payment",
                            TRUE ~ "Late payments for earlier years"))
}

audits <- filter(sources, doc == "audit")
audit_lines <- map(audits$file, read_lines_pdf)
budget_actual <- map2(audit_lines, audits$fy, read_budget_actual) |> list_rbind()
committed <- map2(audit_lines, audits$fy, read_committed) |>
  list_rbind() |>
  distinct()
awards <- map2(audit_lines, audits$fy, read_awards) |> list_rbind()

# QA: each June 30 balance agrees between consecutive audits, and the award schedule
# adds up to the General Fund revenue in every year
stopifnot(!anyDuplicated(committed$fy))
qa_awards <- awards |>
  summarise(awards = sum(amount), .by = fy) |>
  left_join(summarise(budget_actual, actual = sum(actual), .by = fy), by = "fy")
stopifnot(all(abs(qa_awards$awards - qa_awards$actual) < 1))

# budgets FY26-FY28 ----------------------------------------------------------------

# revenue tables: the right-most amount on each impact aid line is the latest column
budget_doc_items <- c(military = "Impact Aid-Military \\(thru", sped = "Impact Aid-Military Spec Ed",
                      dod = "Department of Defense", direct = "Impact Aid-Direct")
read_budget_doc <- function(file) {
  lines <- read_lines_pdf(file)
  imap(budget_doc_items, function(pattern, item) {
    amounts <- lines[str_detect(lines, paste0("^\\s*", pattern))] |>
      map_dbl(\(l) parse_number(last(str_extract_all(l, "[\\d,]+\\.\\d{2}")[[1]])))
    stopifnot(length(amounts) >= 1, n_distinct(amounts) == 1)
    tibble(item, budget = amounts[1])
  }) |>
    list_rbind()
}

later_budgets <- sources |>
  filter(doc != "audit") |>
  mutate(lines = map(file, read_budget_doc)) |>
  select(fy, doc, lines) |>
  unnest(lines) |>
  bind_rows(tibble(fy = 2027, doc = "approved",
                   item = c("military", "sped", "dod", "direct"),
                   budget = c(2100000, 42000, 165000, 8000)))

# budget counted as revenue in each fiscal year: the final budget from the audits for
# FY22-FY25, then the latest available version for FY26-FY28
budget_by_fy <- bind_rows(
  budget_actual |> filter(fy >= 2022) |> mutate(doc = "final"),
  later_budgets
) |>
  summarise(budget = sum(budget), .by = c(fy, doc))
stopifnot(budget_by_fy$budget[budget_by_fy$fy == 2026 & budget_by_fy$doc == "adopted"] == 2689759)
budget_next <- budget_by_fy |>
  filter(doc != "adopted") |>
  transmute(fy_budget = fy, fy = fy - 1, budget_doc = doc, budget_next = budget)

# summary table ------------------------------------------------------------------------

received <- awards |>
  summarise(amount = sum(amount), .by = c(fy, part)) |>
  pivot_wider(names_from = part, values_from = amount, values_fill = 0) |>
  transmute(fy, received_this_year = `This year's payment`,
            received_late = `Late payments for earlier years`,
            received_dod = `Department of Defense`,
            received_total = received_this_year + received_late + received_dod)

impact_aid <- budget_next |>
  left_join(received, by = "fy") |>
  left_join(committed, by = "fy") |>
  rename(fy_received = fy, committed_june30 = committed) |>
  mutate(pct_held_over = 100 * committed_june30 / received_total,
         pct_budgeted_of_received = 100 * budget_next / received_total,
         pct_budgeted_of_committed = 100 * budget_next / committed_june30) |>
  relocate(fy_budget, budget_doc, budget_next, .after = committed_june30) |>
  arrange(fy_received)

write_csv(impact_aid, "data/processed/kibsd_impact_aid.csv")
print(impact_aid |> mutate(across(starts_with("pct"), \(x) round(x, 1))), width = 220)

# style (matches R/05) -----------------------------------------------------------------

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
      panel.grid = element_blank(),
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

# figure: one row per year received, three stages left to right ------------------------

stages <- c("Arrived during the year\n(general fund revenue)", "Held over on June 30\n(committed fund balance)",
            "Counted as revenue in the\nnext year's budget")
parts <- c("This year's payment", "Late payments for earlier years", "Department of Defense")
fills <- c(set_names(c(blue, "#8db8ec", "#cfe0f6"), parts),
           "Held over" = aqua, "Budgeted" = orange, "Projected" = "#f5b49a")
# the small offset rounds exact halves up ($2,425,000 -> $2.43M)
dollars <- \(x) sprintf("$%.2fM", x / 1e6 + 1e-9)

rows <- impact_aid |>
  mutate(row = factor(paste(fy_label(fy_received), "→", fy_label(fy_budget))),
         row = fct_rev(fct_inorder(row)))
audited <- filter(rows, !is.na(received_total))

bars <- bind_rows(
  audited |>
    select(row, all_of(c(`This year's payment` = "received_this_year",
                         `Late payments for earlier years` = "received_late",
                         `Department of Defense` = "received_dod"))) |>
    pivot_longer(-row, names_to = "fill", values_to = "amount") |>
    mutate(stage = stages[1]),
  audited |> transmute(row, fill = "Held over", amount = committed_june30, stage = stages[2]),
  rows |> transmute(row, fill = if_else(budget_doc == "projection", "Projected", "Budgeted"),
                    amount = budget_next, stage = stages[3])
) |>
  mutate(stage = factor(stage, stages), fill = factor(fill, names(fills)))

budget_note <- c(final = "", `winter revision` = "  revised", approved = "  approved",
                 projection = "  projected")
labels <- bind_rows(
  audited |> transmute(row, stage = stages[1], x = received_total, label = dollars(received_total)),
  audited |> transmute(row, stage = stages[2], x = committed_june30,
                       label = sprintf("%s  (%.0f%%)", dollars(committed_june30), pct_held_over)),
  rows |> transmute(row, stage = stages[3], x = budget_next,
                    label = if_else(is.na(received_total),
                                    paste0(dollars(budget_next), budget_note[budget_doc]),
                                    sprintf("%s  (%.0f%%)%s", dollars(budget_next),
                                            pct_budgeted_of_received, budget_note[budget_doc])))
) |>
  mutate(stage = factor(stage, stages))

pending_fy <- setdiff(rows$fy_received, audited$fy_received)
pending <- rows |>
  filter(fy_received %in% pending_fy) |>
  transmute(row, label = if_else(fy_received == max(fy_received),
                                 paste(fy_label(fy_received), "under way"),
                                 paste(fy_label(fy_received), "audit not yet published"))) |>
  cross_join(tibble(stage = factor(stages[1:2], stages)))

pct_committed <- range(audited$pct_budgeted_of_committed)
typical <- filter(audited, pct_budgeted_of_received >= 90)
low <- filter(audited, pct_budgeted_of_received < 90)
stopifnot(nrow(low) == 1)
p <- ggplot(bars, aes(amount, row)) +
  geom_col(aes(fill = fill), position = position_stack(reverse = TRUE), width = 0.62,
           colour = surface, linewidth = 0.4) +
  geom_text(data = labels, aes(x, label = label), hjust = 0, nudge_x = 6e4,
            family = font, size = 3.1, colour = ink2) +
  geom_text(data = pending, aes(0, label = label), hjust = 0, family = font, fontface = "italic",
            size = 3, colour = muted) +
  facet_wrap(~stage, nrow = 1) +
  scale_fill_manual(values = fills, breaks = parts, name = NULL) +
  scale_x_continuous(limits = c(0, 5.3e6), expand = expansion(0)) +
  labs(
    title = "Federal impact aid: received in one year, budgeted the next",
    subtitle = sprintf(paste0(
      "Kodiak Island Borough School District general fund. The next year's budget counted %.0f–%.0f%% of ",
      "what arrived, except in %s (%.0f%%).\nEvery budget from %s to %s counted at least the full amount ",
      "held over on June 30 as revenue (%.0f–%.0f%% of it)."),
      min(round(typical$pct_budgeted_of_received)), max(round(typical$pct_budgeted_of_received)),
      fy_label(low$fy_budget), low$pct_budgeted_of_received, fy_label(min(audited$fy_budget)),
      fy_label(max(audited$fy_budget)), round(pct_committed[1]), round(pct_committed[2])),
    x = NULL, y = NULL,
    caption = paste0(
      "Impact aid: the general fund's military, military special education, Department of Defense and ",
      "direct impact aid; construction impact aid (a separate fund) is not included.\n",
      "Arrived: revenue booked during the fiscal year, split by entitlement year using the schedule of ",
      "federal awards. Percentages are shares of what arrived.\n",
      "Held over: general fund balance committed to impact aid by the Board on June 30.\n",
      "Next year's budget: final budget (FY22–FY25), winter revision (FY26), approved budget (FY27) and ",
      "January 2026 projection (FY28).\n",
      "Sources: KIBSD audited financial statements FY21–FY25, FY26 budget book and revisions, and FY28 ",
      "revenue projections (kibsd.org); KIBSD Board Retreat packet, October 31, 2026.")
  ) +
  theme_pub() +
  theme(axis.text.x = element_blank(), axis.text.y = element_text(colour = ink2, size = rel(1.0)),
        legend.position = "top", legend.justification = "left", legend.location = "plot",
        legend.text = element_text(colour = ink2, size = rel(0.85)),
        legend.key.size = unit(0.8, "lines"), legend.margin = margin(0, 0, 2, 0),
        panel.spacing.x = unit(1.2, "lines"))

save_png(p, "figs/kibsd_impact_aid_carryover.png", width = 12, height = 6.3)
