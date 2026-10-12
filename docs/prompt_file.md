# AK-standardized-tests prompts

# Data downloads 
- Download AK STAR data for all Alaska school districts.
- Download NAEP for Alaska and all other states.
- Are there Kodiak NAEP results? If so, download these.
- Download the best economic indicators available to compare across all Alaska districts. I assume that the best is household median income.
- Run download scripts and QA/QC, summarize what is available.

# Compare Kodiak and other districts
- Use child poverty rate as the economic indicator.
- Plot median AK STAR scores (y-axis) against child poverty rate (x-axis), with district as the sampling unit.
- Make bubble size correspond to district enrollment.
- Fit a regression.
- Highlight Kodiak's relationship to expected (residual value).
- Label Kodiak with text, along with a selected representative set of other districts across the range of values.
- Evaluate the effect of including/excluding districts with very high correspondence populations.
- Summarize which comparisons (grade/subject) are possible before proceeding.
- For now, average across all years of available data, but highlight any important variability in outcomes for Kodiak that might be hidden by that approach.

# Iterate
- Make a version of the main figure (regression) that is fit to 8th and 9th grade results separately. So two columns (English/Math) and two rows (8th/9th).

# Check
- Are there any data available for higher grades than 9th?
- Are there any science data available?

# Science
- Query statewide science data for 2022-2026.
- Make the same plots as for English and math.

# Fix
- The English/match 8th/9th grade four-panel plot has an error in one panel title.
- It reads NA instead of "9th grade - Math".
- Fix this.

# Query
- What districts are the ones at similar size and poverty rate compared to Kodiak that are consistently above the regression lines?

# Edit
- Change all of the plots to label Sitka, Petersburg, Cordova, and Kenia Peninsula.
