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
   - Writes `figs/kodiak_vs_districts_poverty.png` (all grades), `figs/kodiak_vs_districts_poverty_grades_8_9.png` (2×2: grades 8 and 9 × ELA and math, separate fit per panel) and `figs/kodiak_vs_districts_poverty_science.png` (2×2: all tested grades, 5, 8, 10).
   - Also writes `figs/diagnostics/kodiak_residuals_by_year_grade.png` (ELA, math, science) and `figs/diagnostics/correspondence_sensitivity.png` (three panels).
   - **Labels (prompt "Edit", 2026-10-12):** the poverty figures label only Kodiak and its four peers (Sitka, Petersburg, Cordova, Kenai Peninsula); these replaced the earlier spread-out set.
     - The peers are drawn opaque, with a caption line explaining why they are labeled.
     - Sitka, Petersburg and Cordova labels are stacked to the left with leader lines, because the three sit within half a point of child poverty; Kenai's label goes to the right.
     - Grey reference labels across the poverty range were added back on request: Anchorage (9.5%), North Slope (13%), Nome (17%), Lower Kuskokwim (29%), Yupiit (42%). Their bubbles stay faded, and Anchorage's label is pushed below the low-poverty cluster.
     - The correspondence diagnostic still labels the six non-local districts.
   - Both poverty figures come from one function, `poverty_fit_plot()`, which fits each panel separately.
   - Writes `data/processed/district_prof_poverty.csv` and `kodiak_fit_summary.csv`.
   - Needs ggrepel (installed 2026-10-12).
6. `R/06_kodiak_peer_districts.R`: residuals for every district (pooled, by year, by grade) to find Kodiak's peers above the line. Writes `data/processed/kodiak_peer_residuals.csv`.

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
