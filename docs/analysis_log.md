# AK-standardized-tests analysis log

The running record of this project: run order, results, decisions, conventions and open items. Read this first when resuming.

## Purpose

Simple analyses of publicly available data on Alaska standardized test results. The products are polished, informative graphics for the general public.

## Layout

- `R/`: analysis and plotting scripts, numbered by run order
- `data/raw/`: downloaded source files, left as downloaded
- `data/processed/`: cleaned tables written by the scripts
- `figs/`: finished graphics
- `docs/prompt_file.md`: prompts, sent by selecting a section in the IDE

## Run order

Run every script from the project root (`Rscript R/xx.R`). Console output goes to `logs/` (gitignored).

1. `R/01_download_akstar.R`: scrapes DEED's results web app for AK STAR (2023–2026) and, since 2026-10-12, the Alaska Science Assessment (2022–2026). One function, `scrape_test()`, handles both.
   - Saves each page to `data/raw/akstar/html/` and `data/raw/science/html/` (both gitignored).
   - Parses to `data/processed/akstar_{grade,subgroup,districts}.csv` and `science_{grade,subgroup,districts}.csv`.
   - A fresh run takes about 35 minutes at 1 s between requests. Re-runs only fetch missing pages, so re-parsing takes about 1 minute.
2. `R/02_download_naep.R`: NAEP Data Service API, 228 calls, about 10–20 minutes.
   - Writes `data/raw/naep/naep_api_raw.csv` (gitignored, 29 MB) and `naep_call_log.csv`, then `data/processed/naep_states.csv` (24 MB).
3. `R/03_download_econ.R`: Census files, no API key needed. Under 1 minute.
   - ACS rows are filtered to the US, Alaska and Alaska districts and saved in `data/raw/census/`, along with the SAIPE files.
   - Writes `data/processed/acs_district.csv` and `saipe_district.csv`.
4. `R/04_crosswalk_qaqc.R`: links DEED districts to Census/NCES LEAIDs and runs the QA/QC checks.
   - Writes `data/processed/district_crosswalk.csv` and `district_indicators.csv`.
   - Prints the QA report to `logs/04_crosswalk_qaqc.log`.
5. `R/05_kodiak_district_comparison.R`: Kodiak vs other districts, % proficient vs child poverty (prompt "Compare Kodiak and other districts").
   - Writes `figs/kodiak_vs_districts_poverty.png` (all grades), `figs/kodiak_vs_districts_poverty_grades_8_9.png` (2×2: grades 8 and 9 × ELA and math, separate fit per panel), `figs/kodiak_vs_districts_poverty_grades_8_9_low_poverty.png` (blow-up of that figure's left side, every district labeled) and `figs/kodiak_vs_districts_poverty_science.png` (2×2: all tested grades, 5, 8, 10).
   - Also writes `figs/diagnostics/kodiak_residuals_by_year_grade.png` (ELA, math, science) and `figs/diagnostics/correspondence_sensitivity.png` (three panels).
   - **Public by-grade figure (2026-10-29):** `figs/kodiak_residuals_by_grade.png` is a single-panel public version of the by-grade half of the diagnostic: Kodiak's residual by grade, all years combined, for English, math and science.
     - Title: "Kodiak vs. the score expected for its child poverty rate" (Mike's wording, 2026-10-29; it replaced "Kodiak's scores fall furthest below expected in high school"). Subtitle: "Share of students proficient or advanced, by grade (all years combined)".
     - The zero line is labeled "Expected for Kodiak's child poverty rate". Saved at 8.1 × 6 in.
     - Mike removed the high-school band and label and the 9th-grade math callout, and narrowed the figure by 10% (2026-10-29).
     - The caption explains "expected" and notes Kodiak's higher high-school participation (83% of 9th graders vs. 72% statewide; 80% of 10th graders vs. 67%, all years pooled). Higher participation may make Kodiak look slightly worse.
     - Colours follow the diagnostic (English blue, math orange, science green). In the poverty figures, orange marks Kodiak.
   - **Labels (prompt "Edit", 2026-10-12):** the poverty figures label only Kodiak and its four peers (Sitka, Petersburg, Cordova, Kenai Peninsula); these replaced the earlier spread-out set.
     - The peers are drawn opaque, with a caption line explaining why they are labeled.
     - Sitka, Petersburg and Cordova labels are stacked to the left with leader lines, because the three sit within half a point of child poverty; Kenai's label goes to the right.
     - Grey reference labels across the poverty range were added back on request: Anchorage (9.5%), North Slope (13%), Nome (17%), Lower Kuskokwim (29%), Yupiit (42%). Their bubbles stay faded, and Anchorage's label is pushed below the low-poverty cluster.
     - The correspondence diagnostic still labels the six non-local districts.
   - Both poverty figures come from one function, `poverty_fit_plot()`, which fits each panel separately.
   - Writes `data/processed/district_prof_poverty.csv` and `kodiak_fit_summary.csv`.
   - Needs ggrepel (installed 2026-10-12).
6. `R/06_kodiak_peer_districts.R`: residuals for every district (pooled, by year, by grade) to find Kodiak's peers above the line. Writes `data/processed/kodiak_peer_residuals.csv`.
7. `R/07_kibsd_enrollment_by_school.R`: KIBSD enrollment by school, 2016-17 to 2025-26, plus ADM by school for 2025-26 and preliminary 2026-27, and the year-on-year change figure (prompts "KIBSD ADM", "KIBSD preliminary ADM", 2026-11-04, and "Decline plot", 2026-11-05). Under 1 minute.
   - Downloads 13 DEED files to `data/raw/deed_enrollment/` (about 3 MB in all) and KIBSD's FY26 winter budget revision to `data/raw/kibsd_finance/`, skipping any already there. The 2025-26 ADM by school is read from the winter revision pdf. The 2026-27 ADM is typed into the script from the board retreat packet (an image table) and checked against its printed totals.
   - Writes `data/processed/kibsd_enrollment_by_school.csv`, `figs/kibsd_town_enrollment_total.png` and `figs/kibsd_town_enrollment_by_school.png` (a "Total town schools" panel, then one panel per town school and AKTEACH, each with its own y scale) and `figs/kibsd_enrollment_yoy_change.png` (year-on-year % change for town buildings, rural schools, AKTEACH and the district).
8. `R/08_kibsd_impact_aid.R`: KIBSD federal impact aid, received vs held over vs budgeted the next year, FY21–FY28 (prompt "Tracking federal aid in the budget", 2026-11-05). About 1 minute.
   - Downloads 8 kibsd.org files to `data/raw/kibsd_finance/` (about 50 MB, mostly the five audits), skipping any already there. Parses the audits with regexes and checks them: the federal awards schedule must add up to General Fund impact aid revenue in every year.
   - Writes `data/processed/kibsd_impact_aid.csv` and `figs/kibsd_impact_aid_carryover.png`.

## Data sources

### AK STAR (Alaska DEED)
- **Where it lives:** https://education.alaska.gov/assessments/results.
  - DEED posts no bulk AK STAR file; the xlsx files on the yearly pages are the Alternate Assessment.
  - Results are served by the `assessment-results` web app: one page per district and year, plus subgroup pages that need a session cookie.
  - DEED's firewall rejects curl's default user agent, but accepts an honest "R httr2 (...)" agent.
- **Years:** spring 2023–2026, i.e. school years 2022-23 to 2025-26. `year` in the processed files is the spring test year. Spring 2026 results were released on 2026-09-03.
- **Content:** ELA and math, grades 3–9 and "All Grades", at state and district level.
  - Each row has counts and percentages for Advanced/Proficient and Approaching/Needs Support, plus enrollment and participation rate.
  - Only the combined two levels are published, not the four levels separately.
- **Subgroups:** pulled for All Grades only (24 groups: sex, race, economically disadvantaged, disability, English learner, migrant, military parent, homeless, foster care). The `subgroup_grades` setting in script 01 extends this to single grades.
- **Districts:** 54 in 2023–2024 and 53 in 2025–2026.
  - Tanana City SD (DEED ID 53) reported through 2023-24 and has since closed. It is missing from DEED's dropdown, which lists current districts only, so script 01 requests it explicitly through `closed_district_ids`.
  - Mount Edgecumbe (ID 98) is the state boarding school.
- **Suppression:**
  - No results when fewer than 5 students are tested (`*`, `suppressed = TRUE`).
  - If either level has 0–2 students, DEED reports a range ("90% or more", "5% or fewer") and withholds the counts. These rows have `pct_is_range = TRUE`, and their bounds are kept in `prof_pct_min` / `prof_pct_max`.
  - The range depends on the number tested: 5 → 60%, 8 → 75%, 10 → 80%, 20 → 90%, 40+ → 95%.
  - **Ranges matter at district level.** Kashunamiut, Yupiit and St. Mary's (most years) and Yukon Flats (some years) are "5% or fewer" proficient at All Grades with 90–280 students tested; Hydaburg is "10% or fewer". A graphic must show these as ≤5% (or ≤10%), not drop them.
- **`tested` column:** proficient + not proficient. For range rows it is recovered as participation × enrollment, flagged by `tested_from_participation`. The recovery is exact in 2026 and within a few students before.
- **Participation rate:** in 2026 it equals tested ÷ enrollment exactly. In 2023–2025 about 8% of rows differ by 1 point or more (up to 22). DEED's published value is kept; use `tested` as the denominator.
- **Series history** (corrected 2026-10-12; DEED's web app labels 2021-22 as AK STAR and 2020-21 as PEAKS):
  - PEAKS ran in spring 2017–2019 and 2021.
  - AK STAR began in spring 2022, under cut scores set in summer 2022.
  - In January 2024 the State Board lowered the AK STAR cut scores. The spring 2023 results were first released, in April 2024, under the revised cuts.
  - So 2023–2026 form one comparable series. 2022 is not comparable (original cut scores), and PEAKS is not comparable with either.
- **No district scale scores:** DEED's district/school summary reports give mean and median scale scores, but they appear only in individual school-board packets, not in any public statewide dataset. % proficient/advanced is the only district-wide metric.

### NAEP
- **Source:** NAEP Data Service API (`GetAdhocData.aspx`).
  - One `variable` per call; several `stattype`s per call are fine.
  - Statistics reported as 999 with `isStatDisplayable = 0` did not meet NAEP reporting standards. They are set to NA.
- **Pulled:** reading and math, grades 4 and 8, all 50 states plus DC, DoDEA (DS) and national public (NP), every state-level year.
  - Statistics: mean score; % below Basic, at/above Basic, at/above Proficient, Advanced (`ALC:*`), with standard errors.
  - Breakdowns: all students (TOTAL), economically disadvantaged (ECONDIS), race/ethnicity (SDRACE), gender (GENDER).
  - State results before 2000 (math) and 1998 (reading) exist only in the "accommodations not permitted" R2 sample. The `sample` column records which sample each row comes from.
- **Alaska coverage:**
  - Math (grades 4 and 8): 1996 (R2 sample) and 2003–2024.
  - Reading (grades 4 and 8): 2003–2024.
  - Alaska is NA in 2000 math and 1998/2002 reading.
  - On NAEP's own trend charts, the 1996 R2 → 2003 R3 step mixes two samples.
- **Economic disadvantage variable:** `ECONDIS`. In 2024 NAEP relabeled school-lunch eligibility (`SLUNCH3`, which is empty for 2024) as economic disadvantage status, and `ECONDIS` carries the earlier years for trends.
  - The 5 failed calls are ECONDIS for 1990–1994, before NAEP collected it.
  - NAEP's 2024 SES index is not available for Alaska.
- **Latest year:** 2026 NAEP (administered Jan–Mar 2026) has not been released; the API rejects Year=2026. 2024 is the latest.
- **Kodiak:** there are no Kodiak NAEP results. NAEP reports only states, the nation and 26 large urban districts (the Trial Urban District Assessment), and no Alaska district is among them.

### Economic indicators (Census, plus DEED)
- **API:** the Census API now requires a key. Instead we use the no-key files on www2.census.gov.
- **ACS 2020–2024 5-year, table-based summary files.** Rows for Alaska unified school districts start with `9700000US02`; geography = school district, keyed by NCES LEAID. Tables:
  - B19013 median household income
  - B19301 per capita income
  - B15003 adult educational attainment (% HS+, % bachelor's+)
  - The 2021–2025 ACS is due December 2026.
- **ACS reliability:**
  - Aleutian Region SD median household income is top-coded at $250,001 with no MOE; treat it as unusable.
  - Median household income has CV > 30% in Kashunamiut (53%) and Galena (33%); the median CV is 10%.
  - % bachelor's+ is noisier: CV > 30% in 18 districts.
- **SAIPE school district estimates (income years 2022–2024):** total population, children 5–17, and children 5–17 in poverty.
  - These are the model-based estimates used for Title I.
  - Tanana City SD is in 2022–23 but not 2024.
- **DEED economically disadvantaged share:** derived from AK STAR subgroup enrollment (grades 3–9). It is affected by the Community Eligibility Provision.
- **Crosswalk to DEED:** names match exactly except Nome Public Schools, Wrangell Public School District and Saint Mary's School District, which are mapped by hand in script 04. Mount Edgecumbe has no Census geography; every other DEED district matches.

## QA/QC results (2026-10-12)

Every check in `R/04_crosswalk_qaqc.R` passes. The checks cover:
- **AK STAR internal consistency:** % = n ÷ tested; proficient + not proficient = 100%; grade-level counts sum to All Grades; subgroup "All Students" matches the main page.
- **AK STAR totals:** district enrollments sum exactly to the statewide figure in every year. District tested counts sum to the statewide figure, with small residuals from suppressed districts and approximate recovered counts.
- **NAEP:** means are in range; achievement-level percentages are internally consistent.
- **Census:** coverage; child poverty in 0–100.

Statewide AK STAR, all grades, % proficient or advanced:

| | 2023 | 2024 | 2025 | 2026 |
|---|---|---|---|---|
| ELA | 31.8 | 31.5 | 32.7 | 32.9 |
| Math | 32.5 | 31.1 | 32.2 | 32.2 |
| Participation | 81% | 80% | 80% | 79% |

NAEP 2024: Alaska ranks 50th of 51 (50 states + DC) in grade 4 math, grade 4 reading and grade 8 reading, and 46th in grade 8 math. Alaska was near the national public average in 2003, and the gap has widened since about 2013.

### Non-local (correspondence) enrollment: a key caveat for district comparisons
Six districts run large statewide home-school or correspondence programs. Their AK STAR enrollment is several times the number of children who live in the district:

| District | Enrollment vs local children | Participation |
|---|---|---|
| Galena | 66× | ~15% |
| Nenana | 24× | ~15% |
| Yukon-Koyukuk | 8.7× | 23% |
| Chugach | 8.2× | 30% |
| Denali | 4.6× | 40% |
| Craig | 3.9× | 34% |

- Local Census measures do not describe these students, and low participation makes their proficiency rates unrepresentative.
- `district_indicators.csv` flags them (`nonlocal_enrollment`, ratio > 2). Exclude or mark them in any district income-vs-scores graphic.
- Other districts with low participation (Iditarod, Hydaburg, Chatham, Delta/Greely ~55–70%) deserve a note.

### Which economic indicator?
Spearman correlation with district % proficient (ELA + math, 2023–2026 pooled; 46 districts after excluding non-local enrollment and the top-coded district):

| Indicator | ρ |
|---|---|
| % adults 25+ with bachelor's+ (ACS) | 0.77 |
| Child poverty rate, ages 5–17 (SAIPE 2022–24) | −0.75 |
| Per capita income (ACS) | 0.62 |
| Economically disadvantaged share (DEED) | −0.59 |
| Median household income (ACS) | 0.51 |

Median household income is the weakest of the five. In rural Alaska, large households and high living costs blur its meaning, one district is top-coded, and some estimates are noisy. **SAIPE child poverty is the best economic indicator:** it is annual, describes school-age children, is model-based and so reliable for small districts, and correlates as strongly as adult education. Adult education is as strong but is not strictly economic and is noisy in small districts.

## Kodiak vs other districts (2026-10-12)

### Which comparisons are possible
- **Metric:** % proficient or advanced only. There are no scale scores, so no medians, and no four-level breakdown.
- **Subjects:** ELA and math. Science is a separate test that we have not downloaded.
- **Grades:** grades 3–9 individually, or all grades combined.
  - All grades combined: 47 non-local districts give usable values.
  - Single grades, pooled over 2023–2026: 43–45 districts have values, but only 17–28 of them are exact in every year. The rest include "5% or fewer" style ranges or suppressed years.
- **Years:** 2023–2026 (comparable cut scores).
- **Student groups:** all grades combined only (economically disadvantaged, Alaska Native, military-connected, etc.).
- **Not possible:** Kodiak NAEP results; district medians.

### Methods
- **y:** % proficient or advanced, grades 3–9, pooled over 2023–2026 (total proficient ÷ total tested).
  - Range rows enter at their midpoint, e.g. "5% or fewer" → 2.5%.
  - Suppressed rows (<5 tested) drop out.
- **x:** SAIPE child poverty rate, 2022–2024 pooled.
- **Bubble size:** mean AK STAR enrollment, grades 3–9.
- **Fit:** OLS with each district counted once.
  - Main fit excludes the six non-local-enrollment districts and Mt. Edgecumbe (no Census geography): 47 districts.
  - A quadratic term is not significant (ELA p = 0.36, math p = 0.11).
- **Known issue:** the linear fit dips just below 0% at the highest poverty rates (~−1% at 42%). A logit fit avoids this, with the same residual SD.

### Results

| | ELA | Math |
|---|---|---|
| R² | 0.52 | 0.54 |
| p | 1e−8 | 5e−9 |
| Slope | −1.1 points of proficiency per point of child poverty | −1.2 |
| Kodiak observed | 36.6% | 32.0% |
| Kodiak expected | 37.0% | 37.5% |
| Kodiak residual | −0.5 | −5.5 |
| Kodiak residual percentile | 51st | 32nd |

- **Uncertainty:** Kodiak's 95% prediction interval is about ±23 points. Kodiak's math shortfall is within normal district-to-district scatter, so don't overclaim it.
- **Sensitivity:** Kodiak's child poverty rate is 7.8%. The direction holds under every variant:

| Variant | ELA residual | Math residual |
|---|---|---|
| Main fit | −0.5 | −5.5 |
| Including the six non-local districts | −1.9 | −5.8 |
| Weighted by students tested | −1.4 | −6.0 |
| Logit fit | −2.5 | −7.8 |

### Grades 8 and 9 (prompt "Iterate", 2026-10-12)
Separate OLS fit per grade × subject (43 districts each). Each panel has its own y scale, and bubble size is that grade's mean enrollment. All four fits are significant (p < 1e−6).

| | R² | Kodiak observed | Kodiak expected | Residual | Kodiak residual percentile |
|---|---|---|---|---|---|
| Grade 8 ELA | 0.49 | 35.0% | 37.2% | −2.2 | 40th |
| Grade 8 math | 0.60 | 33.7% | 39.7% | −6.0 | 30th |
| Grade 9 ELA | 0.51 | 29.1% | 39.2% | −10.0 | 19th |
| Grade 9 math | 0.51 | 11.4% | 24.4% | −13.0 | 7th |

Grade 9 math is near the bottom of the 95% prediction interval (9.2–39.6%); about 3 of 43 districts sit further below their expected score.

### Blow-up of the low-poverty end, grades 8 and 9 (prompt "Blow-up on math results", 2026-11-11)
Figure: `figs/kodiak_vs_districts_poverty_grades_8_9_low_poverty.png`, the left side of the 2×2 grade 8/9 figure.
- **Districts shown:** Kenai Peninsula and every district with lower child poverty (≤ 11.4%). That is the same 13 districts in every panel: Unalaska, Valdez, Skagway, Juneau, Fairbanks, Kodiak, Cordova, Sitka, Mat-Su, Petersburg, Anchorage, Ketchikan and Kenai Peninsula.
- **Fit lines:** each line is the full-figure fit to all 43 districts, drawn only over the range shown. Kodiak's expected values are unchanged.
- **Labels and layout:**
  - Every district is labeled, and labels keep clear of each bubble's drawn size.
  - The y axis is free per panel and doesn't start at 0.
  - The Kodiak callout sits below and left of Kodiak, which is empty in all four panels.
  - R² and p moved to the caption.
- **Code:** `poverty_fit_plot()` gained an `x_max` argument. With the default (`Inf`), the three existing poverty figures are byte-identical to before.
- **Title:** "Among Alaska's lower-poverty districts, Kodiak's 9th graders score lowest". The script stops if this stops being true, i.e. if Kodiak is no longer both the lowest score and furthest below the line in both 9th-grade panels.

| Panel (13 districts) | Above the line | Kodiak's rank by residual (1 = furthest above) | Lowest score |
|---|---|---|---|
| 8th ELA | 5 | 10th | Ketchikan 29.5% (Kodiak 35.0%) |
| 8th math | 8 | 12th | Ketchikan 29.4% (Kodiak 33.7%) |
| 9th ELA | 5 | 13th | Kodiak 29.1% (next: Ketchikan 29.7%) |
| 9th math | 7 | 13th | Kodiak 11.4% (next: Ketchikan 16.7%) |

- **Contrasts at about Kodiak's poverty rate (7–9%):**
  - Sitka, Petersburg and Cordova sit 3–22 points above the line in every panel.
  - Juneau and Fairbanks sit 1–5 points below.
  - Ketchikan, at 9.7%, sits 5.5–8 points below in every panel.

### Variability hidden by averaging over years
- **ELA:** improving relative to expectation (residual −3.2, 0.0, −0.5, +0.7 for 2023–2026). Kodiak's ELA rose from 33.6% to 39.5% while the state stayed flat.
- **Math:** below expected every year (−7.4, −3.6, −6.6, −5.0).
- **By grade:** ELA is near expected in grades 3–8. Math is below expected in every grade (−3 to −8).
- **Grade 9 is the outlier:** ELA −10, math −13. Grade 9 math is 11.4% proficient against 24.4% expected and 19.9% statewide, and was 5.7% in 2025.
- **Participation:** Kodiak's fell from 89% (2025) to 84% (2026), the year of its best ELA result.
  - Kodiak tests more of its students than the state overall: 87% vs 81% all grades, and 83.5% vs 72% in grade 9.
  - If non-participants elsewhere are lower scorers, this makes Kodiak look slightly worse than a like-for-like comparison would.

## Science: Kodiak vs other districts (2026-10-12)
Same method as ELA/math: % proficient or advanced pooled over 2022–2026 vs SAIPE child poverty, OLS with each district counted once, non-local districts excluded.

| Panel | Districts | R² | Kodiak observed | Kodiak expected | Residual | Kodiak residual percentile |
|---|---|---|---|---|---|---|
| All tested grades (5, 8, 10) | 47 | 0.50 | 38.7% | 43.9% | −5.2 | 36th |
| Grade 5 | 45 | 0.59 | 45.8% | 50.9% | −5.2 | |
| Grade 8 | 44 | 0.57 | 38.2% | 43.0% | −4.8 | |
| Grade 10 | 43 | 0.53 | 31.4% | 40.1% | −8.7 | |

- **By year:** −9.2, −5.4, −4.5, −3.0, −8.9 for 2022–2026.
- **Sensitivity** (all tested grades): including the six non-local districts gives −6.9, weighting by students tested −5.1, logit fit −6.7.
- **Reading:** Kodiak beats the statewide average in grades 5 and 8 but trails districts with similar child poverty. The pattern matches math, and the shortfall is largest in high school (grade 10), as in grade 9 ELA/math.
- **Comparability:** science pools five years (2022–2026); ELA/math pool four (2023–2026).

## Peer districts consistently above the line (prompt "Query", 2026-10-12)
`R/06_kodiak_peer_districts.R` writes `data/processed/kodiak_peer_residuals.csv`.
- **Peers:** child poverty 3–13% and grades 3–9 enrollment 150–11,000.
- **Residuals:** same line fits as R/05, with residuals for every district. "Subject-years" means 13 fits: ELA and math 2023–2026, science 2022–2026. "Grade fits" means 17: ELA and math grades 3–9, science 5, 8, 10.

| District | Child poverty | Enrollment | Participation | Mean residual | Subject-years above | Grade fits above | ELA 9 / Math 9 / Sci 10 |
|---|---|---|---|---|---|---|---|
| Sitka | 8.3% | ~550 | 93% | +11 | 13/13 | 17/17 | +10 / +11 / +7 |
| Petersburg | 8.6% | ~250 | 98% | +10 | 13/13 | 15/17 | +17 / +8 / +12 |
| Cordova | 8.2% | ~190 | 97% | +8 | 13/13 | 15/17 | +11 / +3 / +7 |
| Kenai Peninsula | 11.4% | ~4,400 | 84% | +4 | 13/13 | 16/17 | 0 / 0 / +5 |
| Delta/Greely | 12.6% | ~520 | 69% | +16 | 13/13 | 17/17 | |
| Mat-Su | 8.6% | ~10,400 | 79% | +4 | 12/13 | 13/17 | about 0 in high school |
| Valdez | 5.8% | ~320 | 92% | +6 | 12/13 | | |

- **Delta/Greely:** largest margin, but low participation, so the margin is likely inflated.
- **Below the line like Kodiak** (Kodiak: 7.8%, ~1,120, 1/13 subject-years above, −10 / −13 / −9 in grades 9/9/10):
  - Ketchikan (9.7%, ~1,100): 0/13 subject-years above.
  - Juneau (7.2%, ~2,200): 2/13.
  - Fairbanks (7.7%, ~6,400): 1/13.
- **Excluded from fits (non-local):** Denali and Craig are also above the line.
- **Takeaway:** the consistently-above peers are mostly smaller Southeast/Prince William Sound towns (Sitka, Petersburg, Cordova, Valdez) plus Kenai and Mat-Su. Kodiak's closest matches in size (Ketchikan, Juneau) are below the line too. Sitka is the best single comparison: similar poverty, half the size, island fishing community, high participation, above the line in every fit.

## Higher grades and science: what exists (checked 2026-10-12)

### Alaska Science Assessment
Same web app with `isScience=True`. Downloaded for 2022–2026 on 2026-10-12: 54/54/54/53/53 districts (Tanana through 2024), 1,073 grade rows and 5,477 subgroup rows. Every QA check in script 04 passes, including exact district-to-state enrollment sums.
- **2017–2019:** grades 4, 8, 10; ~45% proficient statewide.
- **2020:** no test.
- **2021:** grades 5, 8, 10, plus near-empty 9 and 11 rows. All results are suppressed (`*`), with 57% participation.
- **2022–2026:** grades 5, 8, 10; 37–38% proficient statewide every year.
  - Grade 10 participation is low: 66–68% statewide, vs 81–84% in grade 5.
  - The January 2024 cut-score change covered ELA and math; nothing indicates the science cut scores changed. 2022–2026 is a stable series, and not comparable with 2017–2019.
- **District pages:** same layout as AK STAR (one "Science" row per grade), with student-group pages. Kodiak's science page for 2025–26 was checked.

### Grades above 9
- **Grade 10 science** is the only state test above grade 9. AK STAR ELA/math stops at grade 9.
- **Kodiak science vs state, % proficient, 2022–2026:**

| Grade | Kodiak vs state |
|---|---|
| 5 | about equal to or above (−0.5 to +5.1) |
| 8 | mostly above (−3.5 to +12.8) |
| 10 | mixed: +2.1, −4.0, −0.9, +1.1, then −9.2 in 2026 (23.8% vs 33.0%) |

  - These are unadjusted for poverty, which favors Kodiak.
  - The 2026 10th graders are the 2025 9th-grade cohort, which was 5.7% proficient in math.
- **NAEP grade 12:** state results exist only for pilot states (e.g. CT and IA in 2009/2013). Alaska has never had one.
- **Not test scores, but available by district:**
  - DEED dropout rates by district, 1991–2025 (`/Stats/GraduationRates/2 - DropoutRatesByDistrict1991to2025.xlsx`)
  - Graduation-rate data on DEED's Data Center
  - Alaska Performance Scholarship materials (ACPE)
- **ACT/SAT:** no district-level public files found.

### NAEP science
- Alaska has only grade 8 in 2011: 153.5 vs national public 150.7.
- Alaska is not reported in 2009 (grade 4), 2015 (grades 4 and 8) or 2019 (grade 8).

## MAP Growth (NWEA): what exists by district (checked 2026-11-01)
Prompt "MAP data". The question was whether public MAP Growth results could support a district comparison like the AK STAR one.

**Conclusion:** no. District MAP results are not published in any form that covers most districts, so the AK STAR-style regression (40+ districts) cannot be built from the public web.

### How MAP relates to AK STAR
- NWEA builds AK STAR. MAP Growth fall and winter benchmarks (grades 3–9) and the spring AK STAR summative form one "through-year" system. The spring summative also produces the spring MAP benchmark score.
- MAP gives a continuous RIT scale score with national norms (achievement percentiles, conditional growth). That would fill the "no district scale scores" gap noted above.
- MAP is not part of the accountability system.

### DEED's published MAP reports
- DEED posts NWEA reports for every term from fall 2022 to spring 2026 at https://education.alaska.gov/assessments/akstar/results, as about 30 PDFs:
  - Grade Reports
  - Student Growth Summaries
  - Projected Proficiency reports
- Every report is "Network: Alaska DEED", i.e. a statewide total by grade. No report has district or school rows; four were checked, including the winter 2023 "ByNetworkByGrade" file.
- For scale: winter 2026 projected proficiency covers 42,934 students in grades 3–9.

### District board packets
- A few districts post their own NWEA reports or slides in board packets. Those found are Northwest Arctic, Lake & Peninsula, North Slope (BoardBook orgs 1035, 1232, 1316), Lower Yukon and Anchorage.
- Formats and terms differ (aggregate-by-district reports, growth summaries, slides).
- None of Kodiak's peer districts (Sitka, Petersburg, Cordova, Kenai, Ketchikan, Juneau) turned up.
- BoardBook's direct PDF links return HTTP 400 to scripted requests.

### Kodiak
- **Late adopter:** a DEED letter to Senate Education (2023-02-15, akleg session 33 docid 1325) says 52 of 54 districts used MAP Growth in 2022-23. Kodiak and Denali were the exceptions, and Kodiak had "no plan to onboard".
- **Now testing:** KIBSD's 2025-26 assessment calendar has MAP Growth fall and winter in grades 3–11, and spring in grades 10–11.
- **Short record:** Kodiak's MAP history therefore starts in 2023-24 at the earliest. The start year is not confirmed.
- **May 2026 board report:** Kodiak's 2026-05-18 board meeting (BoardBook org 3297, meeting 743104) had an "End of Year Assessment Results Report" covering MAP Growth and DIBELS. The attachment is "FY26 EOY assessment data (3)", file 14154507.
  - It was not retrieved. It needs a manual download from https://meetings.boardbook.org/Public/Agenda/3297?meeting=743104.

### Routes to a district comparison
1. **Data request to DEED** (the only route to all districts): ask for district × grade × subject × term aggregates of number tested, mean RIT and SD, achievement percentile, % projected proficient, and fall-to-spring conditional growth. DEED's state account aggregates every district's MAP data.
   - Contacts: Karen Melin, Assessments Administrator; Kari Quinto, AK STAR coordinator.
2. **Ask Kodiak and its peers directly** for their NWEA district reports. That gives a small-n comparison, not a regression.

## KIBSD enrollment by school (2026-11-04)
Prompt "KIBSD ADM": ADM by building for the last ten years, plotted as a town-schools total and by school.

### ADM by school is available online only for 2025-26 and 2026-27; October 1 enrollment is used before that
Updated 2026-11-05, when Mike asked that every enrollment plot use ADM from the Board's budget presentations (the budget "red sheets" list ADM by school) plus the October retreat's preliminary ADM.
- **DEED:** reports ADM by district only (School Finance, "Average Daily Membership by Districts FY88–FY26"). Its foundation funding page has no school-level files.
- **KIBSD budget documents on kibsd.org:** the WordPress media library only holds files from 2023 on, and the only budget documents in it date from FY26 on.
  - **Actual 2025-26 ADM by school:** the foundation formula page (p. 2) of the FY26 winter budget revision, updated 1/17/2026 (https://www.kibsd.org/wp-content/uploads/2026/01/WINTER-REVISIONS-REVENUE-3-PAGE.pdf). The same page is p. 3 of the January 17, 2026 retreat documents. It lists the schools and "Correspondence" (AKTEACH), and they add to 1,951.15, DEED's FY26 district ADM. This is likely the "red sheet" format.
  - **Projections only:** the FY26 budget book's ADM report (p. 22) is the November 2024 projection for FY26. Its site pages show budgeted ADM (FY25 adopted, FY25 spring revision, FY26 preliminary), not counts. The January 2026 retreat pages show projected FY27–FY28 ADM.
- **Not available:** red sheets for FY17–FY25 would be in BoardBook agenda packets. Those weren't fetched, because BoardBook blocks scripted downloads. If Mike supplies those pages, adding them to R/07 moves the earlier years to ADM.
- **Substitute for earlier years:** DEED's October 1 enrollment by school, K–12 with preschool excluded to match ADM. October 1 falls inside the ADM count period (the 20 school days ending the fourth Friday in October).
- **The two measures differ most for AKTEACH and East** (2025-26 ADM vs October 1 count):

| | ADM | Oct 1 K–12 |
|---|---|---|
| AKTEACH | 240.9 | 279 |
| East | 296.25 | 274 |
| Kodiak High | 506.5 | 517 |
| Kodiak Middle | 390.35 | 397 |
| Main | 203.4 | 203 |
| Peterson | 200.75 | 200 |
| Rural schools | same as October 1 | |

  East's ADM covers preschool to 12th grade, so it likely includes some of East's 67 preschoolers.
- **Check:** each year, district-wide October 1 K–12 enrollment is within 1.6% of the district's ADM:

| | 2016-17 | 2018-19 | 2020-21 | 2022-23 | 2024-25 | 2025-26 |
|---|---|---|---|---|---|---|
| Enrollment | 2,386 | 2,315 | 2,221 | 2,177 | 2,049 | 1,983 |
| ADM | 2,397 | 2,303 | 2,246 | 2,174 | 2,040 | 1,951 |

### Sources (DEED Statistics & Reports)
- **2016-17 and 2017-18:** "School Enrollment by Grade as of October 1" PDFs (files named FY2017 and FY2018).
- **2018-19 and 2019-20:** no by-grade school file is posted. "Teacher and Student Counts by School" gives the same October 1 totals; its 2020-21 file matches the 2020-21 by-grade file exactly.
- **2020-21 to 2025-26:** "Enrollment by School by Grade" spreadsheets, in two layouts (before and after 2023-24).
- **QA:** the schools sum exactly to the district total in every year.

### Town vs rural (KIBSD FY26 budget book)
- **Town:** East, Main, North Star (closed after 2024-25), Peterson, Kodiak Middle and Kodiak High, plus AKTEACH (homeschool).
- **Rural:** Akhiok, Chiniak, Old Harbor, Ouzinkie and Port Lions. Danger Bay, Karluk and Larsen Bay are now closed.
- **The figures:** the town total counts the six buildings, and a second line adds AKTEACH. The by-school figure opens with a "Total town schools" panel (buildings only, no AKTEACH), then the six buildings and AKTEACH. Rural schools (10–40 students each) are in the CSV but not plotted.

### Results, K–12 on October 1
- **Six town buildings:** fell 24%, from 2,095 (2016-17) to 1,591 (2025-26). With AKTEACH, the drop is from 2,237 to 1,870 (−16%).
  - Steps: 2019-20 → 2020-21 (COVID) and every year from 2022-23 on.
- **Kodiak High:** 664 → 517. **Kodiak Middle:** 460 → 397. **Peterson:** 242 → 200.
- **Consolidation:** North Star (221 in 2016-17) was at 161 in 2024-25, then closed. In 2025-26, East became K–3 (274 K–12, plus 67 preschool) and Main became grades 4–5 (203). Before that, all four elementaries were K–5.
- **AKTEACH:** 142 → 279, peaking at 230 in 2020-21. This shift accounts for part of the building decline.

### Preliminary 2026-27 ADM by school (added 2026-11-04)
- **Source:** KIBSD Board Retreat packet, October 31, 2026, p. 22, "Initial ADM results": DEED's District Foundation Summary for the KIBSD 2026-27 Fall OASIS trial (run 10/27/2026, not certified). It gives ADM by school, split into elementary (PK–6) and secondary (7–12), plus intensive-needs counts. Mike's copy is `~/Downloads/20261031 BOE Retreat.pdf`.
- **Transcription:** the table is an image, so the values are typed into R/07. The rows sum across and down to the printed totals (951.08 + 905.65 = 1,856.73).
- **Check:** district ADM goes from 1,951.15 (FY26, DEED) to 1,856.73, a 4.84% drop. That matches the packet's FY27 budget column ("net decline of 4.84%").
- **Plotting (revised 2026-11-05):** the first version joined 2025-26 October 1 enrollment straight to 2026-27 preliminary ADM. That step mixed two measures and was wrong for AKTEACH: it showed a fall of 279 → 268, but ADM to ADM AKTEACH rose 240.9 → 267.9.
  - **Now:** solid lines and filled circles are October 1 enrollment (2016-17 to 2025-26). Dashed lines and open circles are ADM by school (2025-26 from the winter revision, 2026-27 preliminary). Both measures are plotted for 2025-26.
  - **Panel titles:** the open circles no longer mark East and Main's regrouping; the panel titles say it instead ("East (K–3 from 2025–26)", "Main (4–5 from 2025–26)").
  - **CSV:** `adm` is DEED's district ADM for the district total rows, and ADM by school for 2025-26 and 2026-27. `adm_status` is final or preliminary, and `adm_source` names the document. The `students` column was dropped.
- **Results, ADM 2025-26 → 2026-27 preliminary:**

| | 2025-26 | 2026-27 (prelim.) | Change |
|---|---|---|---|
| District | 1,951.15 | 1,856.73 | −4.8% |
| Town buildings | 1,597.25 | 1,487.92 | −6.8% |
| Kodiak High | 506.5 | 479.09 | |
| Kodiak Middle | 390.35 | 395.35 | |
| East | 296.25 | 258.03 | −12.9% |
| Main | 203.4 | 180.2 | |
| Peterson | 200.75 | 175.25 | |
| AKTEACH | 240.9 | 267.91 | +11.2% |
| Rural | 113 | 100.9 | −10.7% |

  Within the rural schools, Port Lions went from 30 to 21.
- **Town buildings since 2016-17:** October 1 enrollment fell 24% (2,095 → 1,591 in 2025-26), then ADM fell another 6.8%. Chained, that is about −29%.

### Year-on-year change by group (added 2026-11-05)
Prompt "Decline plot": percent change from the year before, one panel, four lines: town buildings, rural schools, AKTEACH and the district total. Figure: `figs/kibsd_enrollment_yoy_change.png` (made in R/07).
- **Measure rule:** each change compares two years on the same measure. ADM is used where both years have it, otherwise October 1 enrollment.
  - The district total uses DEED ADM every year, plus the preliminary ADM for 2026-27.
  - The school groups use October 1 counts through 2025-26. The 2026-27 change is ADM to ADM.
- **Groups:**
  - Town buildings: the six buildings, without AKTEACH.
  - Rural: Akhiok, Chiniak, Old Harbor, Ouzinkie and Port Lions, plus Danger Bay, Karluk and Larsen Bay in the years they were open.
- **Revision (prompt "Revise", 2026-11-05):** the figure now shows only the town buildings and the district total, with the y axis scaled to those two lines (about −9% to +1%).
  - **Why:** in the first version, AKTEACH's swings (−32% to +135%) flattened the other lines, and the axis had to be cut at +47% with a triangle marking AKTEACH's 2020-21 jump.
  - **Still computed:** R/07 still prints all four groups to the console. The table below keeps them.
- **Results (% change from the year before):**

| | 17-18 | 18-19 | 19-20 | 20-21 | 21-22 | 22-23 | 23-24 | 24-25 | 25-26 | 26-27p |
|---|---|---|---|---|---|---|---|---|---|---|
| District (ADM) | −0.6 | −3.4 | −2.2 | −0.3 | −1.2 | −2.0 | −3.0 | −3.3 | −4.3 | −4.8 |
| Town buildings | −1.0 | +0.5 | −1.6 | −7.4 | +0.7 | +0.1 | −4.6 | −4.9 | −8.6 | −6.8 |
| Rural | −24.8 | −7.1 | −17.3 | +4.7 | +2.2 | +1.1 | +21.5 | −2.7 | +2.7 | −10.7 |
| AKTEACH | +30.3 | −32.4 | −21.6 | +134.7 | −19.1 | −10.2 | −9.6 | +31.8 | +40.2 | +11.2 |

- **Takeaways:**
  - District ADM has fallen every year since 2016-17, and the drop has grown every year since 2020-21 (−0.3% to −4.8%).
  - The town buildings fell faster than the district in each of the last four years. Rural and AKTEACH swing too much year to year to show a trend.

## KIBSD federal impact aid (2026-11-05)
Prompt "Tracking federal aid in the budget": is impact aid a spending buffer the Board could use for FY28? Mike's hypothesis: no. Impact aid arrives a year ahead, and 100% goes to the next year's revenue line.

### Answer: confirmed. The committed impact aid balance is already in the next year's revenue
- **How it works:** each year's federal payment arrives during the fiscal year and is booked as General Fund revenue that year. At June 30, the Board commits an amount of fund balance to "Impact Aid". The next year's budget counts the impact aid lines as revenue at about that amount.
- **Commitment fully used:** every budget from FY22 to FY26 counted 100–116% of the June 30 commitment as revenue. None of the committed balance is left over.
- **What the district treats as spendable:** "FY26 fund balance $5,864,338" in the FY27 estimated fund balance worksheet equals the General Fund **unassigned** balance at June 30, 2025. The $2,377,462 committed to impact aid is not part of it.
- **Where extra impact aid goes:** receipts above the commitment, such as FY24's $0.71M of late payments for FY2022–FY2023 entitlements plus higher Defense money, fall into unassigned fund balance. That money is already in the district's fund balance projections and "use of fund balance" lines.
- **FY28:** the FY28 budget's impact aid lines will be FY27's payment. The January 2026 FY28 projections already count $2,425,000.
- **The only way to free money:** budget each year's payment in the year it arrives. That would count two years of impact aid once, a one-time gain of roughly one year's payment (about $2.3–2.4M). FY28 would then depend on a payment that arrives during FY28 and whose amount isn't known when the budget is adopted. It can only be done once.

### Data (General Fund; impact aid = military + military special ed + Department of Defense + direct)
| Received in | Arrived | Of which late payments | Committed June 30 | Next budget | Next budget ÷ arrived | Next budget ÷ committed |
|---|---|---|---|---|---|---|
| FY21 | 2,952,596 | 316,393 | 2,518,355 | FY22 final 2,910,058 | 99% | 116% |
| FY22 | 2,593,424 | 195,513 | 2,583,412 | FY23 final 2,587,303 | 100% | 100% |
| FY23 | 2,848,655 | 311,826 | 2,848,011 | FY24 final 2,848,011 | 100% | 100% |
| FY24 | 3,515,433 | 705,947 | 2,561,183 | FY25 final 2,689,759 | 77% | 105% |
| FY25 | 2,544,403 | 0 | 2,377,462 | FY26 revised 2,605,205 (adopted 2,689,759) | 102% | 110% |
| FY26 | audit not out | | | FY27 approved 2,315,000 | | |
| FY27 | under way | | | FY28 projected 2,425,000 | | |

- **What was committed:**
  - FY22 and FY23: about everything received.
  - FY24 and FY25: only that year's own entitlement payment. FY24: $2,561,183 vs the FY2024 payment of $2,561,092. FY25: $2,377,462, exactly the FY2025 payment.
  - FY21: $2,518,355 doesn't match any combination of the lines.
- **Line-level match, FY23 → FY24:** the FY24 final budget repeats FY23 actuals line by line (military $2,617,660; special ed $43,069; DoD $167,407).
- **Accounting policy (audit notes):** "Federal Impact Aid funds are recorded in the year to which the entitlement is received." Before FY25 the note added "including accrual at year end of final payments due within approximately two months after year end."

### Sources (kibsd.org WordPress media library; found through `/wp-json/wp/v2/media`)
- **Audited financial statements FY21–FY25** (`KIBSD-Final-FS-2021` to `-2024`, `FY25-Financial-Statement`). Used:
  - exhibit G-2, General Fund budget vs actual: final budget and actual
  - the General Fund balance sheet: committed Impact Aid
  - the schedule of expenditures of federal awards, ALN 84.041, by entitlement year
- **Budget documents:**
  - FY26 Budget Book (adopted June 16, 2025)
  - FY26 winter revisions (January 2026)
  - FY28 projected revenue scenarios (January 2026)
  - FY27 approved budget: KIBSD Board Retreat packet, October 31, 2026, p. 21 (image table, typed into the script)
- **Read but not used by the script:**
  - FY27 Estimated Fund Balance, updated 1/25/26: https://www.kibsd.org/wp-content/uploads/2026/02/FY27-Estimated-Fund-Balance-updated-1_25_26.docx
  - FY27 financial overviews (12/8/2025 and 1/5/2026)
  - FY26 budget retreat and budget considerations decks (January 2025)
- **Not used:** BoardBook agenda packets. Scripted downloads are blocked there (HTTP 400), and the audits' "final budget" column covers the board-approved budgets.
- **Out of scope here:** the state foundation formula also deducts part of impact aid from state aid. See the next section.

## How the state foundation formula counts impact aid (2026-11-11)
Prompt "State adjustments for federal impact aid": review KIBSD budget documents and summarize how the state adjusts the foundation formula for impact aid. No script or figure. The numbers were copied from the documents and checked with a scratch R script.

### Mechanism
- **State aid = basic need − required local effort − deductible impact aid**, plus Quality Schools. Every KIBSD foundation formula sheet labels the line this way.
- **Deductible impact aid = eligible impact aid × 0.9 × (required local contribution ÷ actual local contribution).** KIBSD's sheets write this as "Impact Aid *.9 * x%", where x% is "Local required/local budget".
  - **The 0.9** comes from AS 14.17.410(b)(1): state aid is basic need minus the required local contribution "and 90 percent of eligible federal impact aid for that fiscal year".
  - **The ratio** is a federal limit (ESEA 7009(d)(1)(B)). The state may count only the share of impact aid that matches required local effort.
  - **"Local budget" in KIBSD's sheets** is the borough appropriation plus facilities, athletic fees and village rent; E-Rate is left out. Example for FY26: 6,703,145 ÷ 13,075,556.50 = 51.26%.
  - **What "eligible" excludes** (U.S. Department of Education (ED) letter, May 16, 2025, p. 3):
    - section 7003(d) payments for children with disabilities;
    - Indian-lands weights above 1.0;
    - heavily impacted 7003(b)(2) amounts above basic support.
  - **Unresolved:** the formula's impact aid figure doesn't match any combination of KIBSD's revenue lines (military, military special ed, Department of Defense, direct). The documents don't show which lines DEED counts.
- **Timing:** DEED applies "federal Impact Aid receipts … to the current year" and the current year's local contribution. It updates them in the spring and settles them in the last three payments of the year (DEED School Finance report to the State Board, March 2026).
  - KIBSD budgets impact aid revenue at the prior year's payment (see the section above). The deduction follows current-year receipts.
- **Federal permission is required.** A state may count impact aid only if ED certifies its formula as equalizing. The test: the 95th-percentile district's revenue per ADM may exceed the 5th-percentile district's by no more than 25%.
  - **FY26: not certified.** ED's May 16, 2025 letter found a disparity of 26.88%, so the state may not count impact aid for July 2025–June 2026.
    - The dispute is over transfers to transportation funds.
    - DEED requested a hearing on July 14, 2025. The appeal was still pending in DEED's March 2026 report and its June 18, 2026 release.
    - KIBSD's January 2026 revision still deducts $1,064,071 for FY26.
    - DEED puts the statewide amount at about $80.8M.
  - **FY27: certified** on June 18, 2026, at a disparity of 21.3%. The deduction applies in FY27.
  - **FY28:** depends on the test DEED submits in spring 2027.

### KIBSD foundation formula sheets
| Sheet | Impact aid in formula | Impact Aid % shown | Deductible shown | Deductible from the sheet's own inputs |
|---|---|---|---|---|
| FY26 budget considerations, Jan 2025 | not shown | not shown | 1,189,924 | – |
| FY26 adopted, budget book, Jun 2025 | 2,507,942 | 51.26% | 1,222,471 | 1,157,014 |
| FY26 winter revision, Jan 17 2026 | 2,306,479 | 51.26% | 1,064,071 | 1,064,071 |
| FY26 fall revision ($700 BSA), Jan 2026 projection file | 2,507,942 | 51.26% | 1,222,471 | 1,157,014 |
| FY27–FY29 projections, Dec 2025–Jan 2026 (17 sheets) | 2,507,942 | 46.38–49.85% | 1,222,471 | 1,046,865–1,125,188 |
| of which FY28, 3% decline, HH, 90 INF | 2,507,942 | 48.14% | 1,222,471 | 1,086,591 |

### Takeaways
- **The state counts about 46% of eligible impact aid as if it were local money.** In the FY26 winter revision, it deducts $1,064,071 of $2,306,479; KIBSD keeps the other 54%.
  - Payments the formula doesn't count are kept in full: military special ed, and probably the Department of Defense supplement.
- **Borough money above the required amount shrinks the deduction.** Below the cap, each extra borough dollar cuts the deduction by about 7–9 cents (derivative of the ratio at FY26–FY29 values).
  - If the borough paid only the required $6.70M, the FY26 deduction would be the full 90% ($2.08M) instead of $1.06M.
- **Only the FY26 winter revision is internally consistent.** Every other sheet since the FY26 adopted budget holds the deduction at $1,222,471, which implies 54.16%. That stays the same whatever percentage the sheet shows.
  - With each sheet's own percentage, the deduction would be $65K–$176K lower, so those sheets understate state aid by that amount.
  - They also keep impact aid at the FY26 adopted figure ($2,507,942). The January 2026 revision lowered it to $2,306,479; at that figure and 48.14%, the FY28 deduction would be about $999K, $223K below the $1,222,471 shown.
- **FY26 is still open.** If DEED loses its appeal, the state may not count impact aid for FY26. For KIBSD, the amount at stake is the $1.06M FY26 deduction. Whether and how districts would be paid is not settled in anything I found.

### Sources
- **KIBSD (kibsd.org media library):**
  - FY26 Budget Book, foundation formula p. 22
  - Winter revisions, Jan 17 2026, p. 2
  - FY27 and FY28/FY29 projected revenue scenarios, Jan 2026
  - FY26 Budget Considerations decks, Jan 2025
  - FY27 Financial Overviews, Dec 2025 and Jan 2026
  - Board Retreat packet, Oct 31 2026, p. 21: revenue only, no formula page
- **ED:** Impact Aid Program determination letter and report for State FY2026, May 16, 2025: https://education.alaska.gov/faq_local_contribution/250516%20ED%20Determination%20Letter_AK-DEED.pdf
- **DEED:**
  - Local contribution FAQ: https://education.alaska.gov/local-contribution-faq
  - School Finance report to the State Board, March 2026: https://education.alaska.gov/State_Board/march-2026/21C_2026-03%20FSS%20Report.pdf
  - FY2027 certification release, June 18, 2026: https://content.govdelivery.com/accounts/AKDEED/bulletins/41cb695
- **Statute:** AS 14.17.410(b)(1).

## Working conventions and user preferences

- **Audience:** the general public. Graphics should explain themselves through a plain-language title, subtitle and source/notes caption.
- **Rendering:** ggplot2 → ragg PNG at publication resolution. System fonts are available through systemfonts: Avenir Next, Helvetica Neue, Futura, Gill Sans and Georgia.
- **Layout:** no added white space. Use independent axes when panels cover different ranges, and side-by-side panels for comparisons.
- **Git:** Mike commits and pushes himself. Commit only when asked. Gitignored: `logs/`, `data/raw/akstar/html/`, `data/raw/naep/naep_api_raw.csv`.

## Environment (2026-10-12)

- R 4.6.0.
- Installed: tidyverse, ggplot2, scales, patchwork, ragg, systemfonts, readxl, httr2, rvest, ggrepel (added 2026-10-12).
- Not installed: ggtext, showtext, geomtextpath, janitor, here, sf, tigris, gt. Install these as needed.

## Open items

- Kodiak figures (ELA/math all grades, grades 8/9, science) are drafts awaiting Mike's review. Possible follow-ups:
  - a grade 9 math look
  - a by-year version
  - student-group comparisons (e.g. economically disadvantaged students only)
  - logit vs linear fit line
- Optional: adjust incomes for Alaska's regional cost of living if income is shown directly.
- Optional: grade-level subgroups (set `subgroup_grades` in script 01; about 3,000 more requests).
- Optional: AK STAR science (Alaska Science Assessment, grades 5/8/10) and school-level results are on the same web app.
