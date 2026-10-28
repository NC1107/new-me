# New Me v17: cardio fitness

Earlier design documents still hold unless a section below changes them.

## Why

Apple Health VO2 max is already synced daily as the `vo2max` metric, but it was shown only as a number.
Cardiorespiratory fitness is among the strongest predictors of all-cause mortality (Mandsager et al.).
Each 1 MET higher goes with about 13% lower risk of death from any cause (Kodama et al.).
The page gives the number a trend, a place among people of the same age and sex, and honest limits.
It adds no quest and no score, because a watch estimate is too noisy to be graded daily.

## The page

- The VO2 max row on the Health list opens Cardio fitness instead of the plain metric trend.
- A segmented control picks 3, 6 or 12 months, as 90, 180 and 365 days.
- The app fetches 365 days once from `GET /api/health/trends` and cuts the shorter windows on the device.
- The chart is the existing `TrendChart`, so no package was added.
- A window with only older readings says "No readings in this window" and points to a longer one.
- With no reading at all the page shows the empty state and still shows the notes on accuracy.
- A card shows the percentile band, the middle value for the group, and the source.
- A card on what moves it states the WHO guidance and the last 7 days of Apple Health exercise minutes.
- A card says the figure is an estimate and gives the published error.

## The comparison

- `GET /api/health/cardio` returns the newest reading, a status and the band.
- The lookup is a pure function, `targets.CardioNorms`, in `server/internal/targets/cardio.go`, beside the other age and sex tables.
- Age comes from `users.birth_year` by calendar year and sex from `users.sex`, read the same way as the targets page.
- Status is `ready`, `no_reading`, `needs_profile` or `age_out_of_range`.
- `needs_profile` lists `birthYear` and `sex`, whichever is missing, and the page names them.
- The reference data covers ages 20 to 89, so younger and older people get `age_out_of_range`.
- A value equal to a table column counts as reaching that percentile.
- The band lies between two neighbouring columns, with "below the 10th" under the first and "above the 90th" over the last, because the table says nothing finer at the ends.
- No migration was added and nothing new is read from HealthKit.

## The norm table

Source: Kaminsky LA, Arena R, Myers J, et al. Updated reference standards for cardiorespiratory fitness measured with cardiopulmonary exercise testing: data from the Fitness Registry and the Importance of Exercise National Database (FRIEND). Mayo Clin Proc 2022;97(2):285-293, Table 3.
The data are 16,278 treadmill tests from 34 laboratories in apparently healthy US adults aged 20 to 89.
Values are peak VO2 in ml/kg/min, with maximal effort taken as a respiratory exchange ratio of at least 1.0.
The paper reports that mean peak VO2 was similar with a ratio cutoff of 1.0 or 1.1.
The 2022 treadmill standards are 1.5 to 4.6 ml/kg/min lower than the 2015 standards (Kaminsky et al., Mayo Clin Proc 2015;90:1515), which is why the 2022 table is used.

### Men

| Age | 10th | 20th | 30th | 40th | 50th | 60th | 70th | 80th | 90th |
|---|---|---|---|---|---|---|---|---|---|
| 20-29 | 28.6 | 35.2 | 40.0 | 43.6 | 46.5 | 49.0 | 51.9 | 54.5 | 58.6 |
| 30-39 | 24.9 | 29.8 | 33.5 | 37.0 | 39.7 | 43.4 | 46.4 | 50.0 | 55.5 |
| 40-49 | 22.1 | 26.7 | 29.7 | 32.4 | 35.3 | 37.9 | 40.9 | 45.2 | 50.8 |
| 50-59 | 18.6 | 22.2 | 24.5 | 26.9 | 29.2 | 31.8 | 34.3 | 38.3 | 43.4 |
| 60-69 | 15.8 | 18.5 | 20.7 | 22.8 | 24.6 | 26.5 | 28.7 | 32.0 | 37.1 |
| 70-79 | 13.6 | 15.9 | 17.3 | 19.1 | 20.6 | 22.2 | 23.8 | 25.9 | 29.4 |
| 80-89 | 12.9 | 14.8 | 16.1 | 16.6 | 17.6 | 18.4 | 20.0 | 21.4 | 22.8 |

### Women

| Age | 10th | 20th | 30th | 40th | 50th | 60th | 70th | 80th | 90th |
|---|---|---|---|---|---|---|---|---|---|
| 20-29 | 22.5 | 27.2 | 30.8 | 34.0 | 36.6 | 39.0 | 41.8 | 44.8 | 49.0 |
| 30-39 | 18.6 | 21.9 | 24.2 | 26.4 | 28.3 | 31.0 | 33.6 | 37.0 | 42.1 |
| 40-49 | 17.2 | 19.7 | 21.8 | 23.9 | 25.7 | 27.7 | 30.0 | 33.0 | 37.8 |
| 50-59 | 16.5 | 18.5 | 20.1 | 21.5 | 22.9 | 24.6 | 26.3 | 28.4 | 32.4 |
| 60-69 | 13.4 | 15.4 | 17.0 | 18.3 | 19.6 | 20.9 | 22.4 | 24.3 | 27.3 |
| 70-79 | 12.3 | 14.0 | 15.2 | 16.2 | 17.2 | 18.3 | 19.6 | 20.8 | 22.8 |
| 80-89 | 11.4 | 12.6 | 13.7 | 14.7 | 15.4 | 16.0 | 17.3 | 18.4 | 20.8 |

### Verification status

The publisher blocked automated access to the full text, so these numbers were transcribed from a secondary site that reproduces Table 3 and names this citation.
A second site prints the same paper's treadmill standards for a ratio of at least 1.10 with other columns (5th, 25th, 50th, 75th, 95th) and slightly lower medians, for example 45.4 for men aged 20 to 29 against 46.5 here.
That fits two effort cutoffs, but neither site is the paper.
Before release, compare every number above with Table 3 of the paper and correct `cardioNorms` if any differ.
The unit tests check that each row rises with percentile and that medians fall with age, which would catch most transcription slips.

## What changes it

- The World Health Organization advises 150 to 300 minutes of moderate or 75 to 150 minutes of vigorous aerobic activity a week for adults (Bull et al., Br J Sports Med 2020;54:1451-1462).
- The American College of Sports Medicine gives similar targets (Garber et al., Med Sci Sports Exerc 2011;43:1334-1359).
- The page shows the Apple Health `exercise_minutes` total for the last 7 days, read from the existing trends endpoint.
- Apple exercise minutes count all brisk activity, so the page says they are not only vigorous.
- No vigorous-only figure exists in the synced data, and no HealthKit read was added.

## How accurate the watch is

- Apple Watch estimates VO2 max from heart rate and movement and is not a lab test.
- Lambe R, O'Grady B, Baldwin M, Doherty C. Investigating the accuracy of Apple Watch VO2 max measurements: a validation study. PLoS One 2025;20(5):e0323741.
- It compared 28 adults against indirect calorimetry and found a mean absolute percentage error of 13.31%, a mean underestimate of 6.07 ml/kg/min and 95% limits of agreement from -6.11 to 18.26.
- Caserman P, Yum S, Goebel S, Reif A, Matura S. Assessing the accuracy of smartwatch-based estimation of maximum oxygen uptake using the Apple Watch Series 7: validation study. JMIR Biomed Eng 2024;9:e59459.
- It compared 19 adults against a portable gas analyzer and found a mean absolute percentage error of 15.79%, a root mean square error of 8.85 ml/kg/min and an ICC(2,1) of 0.47.
- The page therefore says the typical error is 13 to 16 percent and that changes of a point or two are noise.
- Apple's own validation study was not available to read, so it is not cited.

## Sources

- Mandsager K, et al. Association of cardiorespiratory fitness with long-term mortality among adults undergoing exercise treadmill testing. JAMA Netw Open 2018;1(6):e183605.
- Kodama S, et al. Cardiorespiratory fitness as a quantitative predictor of all-cause mortality and cardiovascular events in healthy men and women: a meta-analysis. JAMA 2009;301(19):2024-2035.
- Kaminsky LA, et al. Reference standards for cardiorespiratory fitness measured with cardiopulmonary exercise testing: data from the FRIEND registry. Mayo Clin Proc 2015;90:1515-1523.
- Kaminsky LA, et al. Updated reference standards, Mayo Clin Proc 2022;97(2):285-293.
- Bull FC, et al. World Health Organization 2020 guidelines on physical activity and sedentary behaviour. Br J Sports Med 2020;54:1451-1462.
- Garber CE, et al. Quantity and quality of exercise for developing and maintaining cardiorespiratory, musculoskeletal, and neuromotor fitness in apparently healthy adults. Med Sci Sports Exerc 2011;43:1334-1359.
