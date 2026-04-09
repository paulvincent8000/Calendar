/* General Purpose Calendar – Baden-Württemberg with public holidays

   Date range: 1 January (current year minus 5) to 31 December (current year).

   Two reference dates drive all period calculations:
     ref_d  – yesterday (last closed day)
     ref_m  – last day of the prior month (last closed month)

   Naming convention: IS_[PERIOD+SCOPE]_[DIRECTION]
     Period+scope: ytd, ytm, qtd, qtm, mtd, full_year, full_quarter,
                   full_month, full_week, rolling_12m
     Direction:    cy (current year), py (prior year), ay (any year)

   Flag anchor logic:
     cy/py daily flags (ytd, qtd, mtd)  → upper bound = ref_d
     cy/py monthly flags (ytm, qtm)     → upper bound = ref_m
     full_* flags                        → full calendar period, includes future days
     rolling_12m                         → last 12 full completed months (ref_m anchor)

   Usage: copy the full query and delete the flag sections not required.
*/

WITH

-- ── Reference dates & date range ─────────────────────────────────────────────
ref AS (
    SELECT
        DATEADD(day, -1, CURRENT_DATE())                       AS ref_d,
        DATEADD(day, -1, DATE_TRUNC('month', CURRENT_DATE()))  AS ref_m,
        DATE_TRUNC('year', DATEADD(year, -5, CURRENT_DATE()))  AS range_start,
        DATE_TRUNC('year', DATEADD(year,  1, CURRENT_DATE()))  AS range_end
),

-- ── Date generation ──────────────────────────────────────────────────────────
-- ROWCOUNT => 2200 is a sufficient ceiling for a ~6-year window.
date_scaffold AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS day_offset
    FROM TABLE(GENERATOR(ROWCOUNT => 2200))
),

-- 1 January five years ago to 31 December of the current year
calendar_base AS (
    SELECT DATEADD(day, day_offset, r.range_start) AS date
    FROM date_scaffold
    CROSS JOIN ref r
    WHERE DATEADD(day, day_offset, r.range_start) < r.range_end
),

dates AS (
    SELECT

    -- ════════════════════════════════════════════════════════════════════════
    -- Core date attributes (required — do not delete)
    -- ════════════════════════════════════════════════════════════════════════
    date,
    YEAR(date)                                          AS year_int,
    'Q' || QUARTER(date)                                AS quarter_of_year,
    TO_CHAR(date, 'MMMM')                               AS month_name,
    TO_CHAR(date, 'MON')                                AS month_name_short,
    WEEKOFYEAR(date)                                    AS week_of_year,
    DATE_TRUNC('week', date)                            AS week_start_date,
    DATEADD(day, 6, DATE_TRUNC('week', date))           AS week_end_date,
    DECODE(DAYOFWEEK(date),
        0,'Sunday', 1,'Monday', 2,'Tuesday',
        3,'Wednesday', 4,'Thursday',
        5,'Friday', 6,'Saturday'
        )                                               AS day_of_week_name,
    TO_CHAR(date, 'DY')                                 AS day_of_week_name_short,
    DAYOFWEEK(date)                                     AS day_of_week,   -- 0 = Sunday, 6 = Saturday
    MONTH(date)                                         AS month_int,
    DAY(date)                                           AS day_int,

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 01 · Time Offsets
    -- Positive = past, negative = future
    -- ════════════════════════════════════════════════════════════════════════
    DATEDIFF('day',     date, CURRENT_DATE())           AS offset_day,
    DATEDIFF('week',    date, CURRENT_DATE())           AS offset_week,
    DATEDIFF('month',   date, CURRENT_DATE())           AS offset_month,
    DATEDIFF('quarter', date, CURRENT_DATE())           AS offset_quarter,
    DATEDIFF('year',    date, CURRENT_DATE())           AS offset_year,

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 02 · Full Period Flags  (is_full_*)
    -- Complete calendar periods — includes future days within the period.
    -- ════════════════════════════════════════════════════════════════════════
    MONTH(date) = MONTH(CURRENT_DATE())
        AND date <= r.ref_d                             AS is_full_month_ay, -- Full month, any year, daily anchor
    YEAR(date)  = YEAR(CURRENT_DATE())
        AND MONTH(date) = MONTH(CURRENT_DATE())         AS is_full_month_cy, -- Full current month
    date >= DATE_TRUNC('month', r.ref_m)
        AND date <= r.ref_m                             AS is_full_month_py, -- Full prior month
    YEAR(date)    = YEAR(CURRENT_DATE())
        AND QUARTER(date) = QUARTER(CURRENT_DATE())     AS is_full_quarter_cy, -- Full current quarter
    date >= DATE_TRUNC('quarter', r.ref_m)
        AND date <  DATE_TRUNC('quarter', CURRENT_DATE()) AS is_full_quarter_py, -- Full prior quarter
    date >= DATE_TRUNC('week', CURRENT_DATE())
        AND date <  DATEADD(week, 1,
            DATE_TRUNC('week', CURRENT_DATE()))         AS is_full_week_cy,  -- Full current week
    date >= DATE_TRUNC('week', DATEADD(week, -1, CURRENT_DATE()))
        AND date <  DATE_TRUNC('week', CURRENT_DATE())  AS is_full_week_py,  -- Full prior week
    YEAR(date) = YEAR(CURRENT_DATE())                   AS is_full_year_cy,  -- Full current year
    YEAR(date) = YEAR(CURRENT_DATE()) - 1               AS is_full_year_py,  -- Full prior year

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 03 · Month to Date  (is_mtd_*)
    -- Month start → ref_d (daily anchor)
    -- ════════════════════════════════════════════════════════════════════════
    MONTH(date) = MONTH(CURRENT_DATE())
        AND DAY(date) <= DAY(r.ref_d)                   AS is_mtd_ay,        -- MTD position, any year
    date >= DATE_TRUNC('month', CURRENT_DATE())
        AND date <= r.ref_d                             AS is_mtd_cy,        -- MTD current month → ref_d

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 04 · Quarter to Date / Quarter to Month  (is_qtd_*, is_qtm_*)
    -- QTD: quarter start → ref_d (daily anchor)
    -- QTM: quarter start → ref_m (monthly anchor)
    -- ════════════════════════════════════════════════════════════════════════
    date >= DATE_TRUNC('quarter', CURRENT_DATE())
        AND date <= r.ref_d                             AS is_qtd_cy,        -- QTD current quarter → ref_d
    date >= DATE_TRUNC('quarter', DATEADD(month, -3, CURRENT_DATE()))
        AND date <= DATEADD(month, -3, r.ref_d)         AS is_qtd_py,        -- QTD prior quarter → (ref_d − 1 quarter)
    date >= DATE_TRUNC('quarter', CURRENT_DATE())
        AND date <= r.ref_m                             AS is_qtm_cy,        -- QTM current quarter → ref_m

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 05 · Rolling 12 Months  (is_rolling_12m_*)
    -- Full completed months only; never includes the current open month.
    -- cy: most recent 12 full months; py: the 12 full months before that.
    -- ════════════════════════════════════════════════════════════════════════
    date >= DATE_TRUNC('month', DATEADD(month, -12, CURRENT_DATE()))
        AND date <= r.ref_m                             AS is_rolling_12m_cy, -- Rolling 12 months, current window
    date >= DATE_TRUNC('month', DATEADD(month, -24, CURRENT_DATE()))
        AND date <  DATE_TRUNC('month',
            DATEADD(month, -12, CURRENT_DATE()))        AS is_rolling_12m_py, -- Rolling 12 months, prior window

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 06 · Year to Date / Year to Month  (is_ytd_*, is_ytm_*)
    -- YTD: Jan 1 → ref_d (daily anchor)
    -- YTM: Jan 1 → ref_m (monthly anchor)
    -- ════════════════════════════════════════════════════════════════════════
    (MONTH(date) < MONTH(r.ref_d))
        OR (MONTH(date) = MONTH(r.ref_d)
            AND DAY(date) <= DAY(r.ref_d))              AS is_ytd_ay,        -- YTD position, any year
    date >= DATE_TRUNC('year', CURRENT_DATE())
        AND date <= r.ref_d                             AS is_ytd_cy,        -- YTD current year → ref_d
    date >= DATE_TRUNC('year', DATEADD(year, -1, CURRENT_DATE()))
        AND date <= DATEADD(year, -1, r.ref_d)          AS is_ytd_py,        -- YTD prior year → (ref_d − 1 year)
    date >= DATE_TRUNC('year', CURRENT_DATE())
        AND date <= r.ref_m                             AS is_ytm_cy,        -- YTM current year → ref_m
    date >= DATE_TRUNC('year', DATEADD(year, -1, CURRENT_DATE()))
        AND date <= DATEADD(year, -1, r.ref_m)          AS is_ytm_py,        -- YTM prior year → (ref_m − 1 year)

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 07 · Status & Maturity Flags
    -- ════════════════════════════════════════════════════════════════════════
    date <= r.ref_d                                     AS is_past,          -- Date is on or before ref_d
    date <= r.ref_m                                     AS is_past_full_month, -- Date is on or before ref_m (month fully elapsed)
    date = CURRENT_DATE()                               AS is_today,
    DAYOFWEEK(date) IN (0, 6)                           AS is_weekend,
    date = r.ref_d                                      AS is_yesterday

    FROM calendar_base
    CROSS JOIN ref r
),

-- ════════════════════════════════════════════════════════════════════════════
-- Holiday logic – Baden-Württemberg
-- ════════════════════════════════════════════════════════════════════════════

-- Easter Sunday: Anonymous Gregorian algorithm (Meeus simplified)
-- Formula: Easter = March 22 + d + e
--   d = (19a + 24) mod 30,  where a = year mod 19
--   e = (2b + 4c + 6d + 5) mod 7,  where b = year mod 4, c = year mod 7
-- Known exceptions (outside the calendar's rolling window):
--   d=29, e=6        → formula gives Apr 26; correct is Apr 19  (next: 2076)
--   d=28, e=6, a>10  → formula gives Apr 25; correct is Apr 18  (next: 2049)
easter_base AS (
    SELECT DISTINCT
        year_int,
        (19 * (year_int % 19) + 24) % 30                                        AS d,
        (2 * (year_int % 4) + 4 * (year_int % 7)
            + 6 * ((19 * (year_int % 19) + 24) % 30) + 5) % 7                  AS e
    FROM dates
),

easter_dates AS (
    SELECT
        year_int,
        DATEADD(day, d + e, TO_DATE(year_int || '-03-22', 'YYYY-MM-DD')) AS easter_date
    FROM easter_base
),

bw_holidays AS (
    SELECT
        c.date,
        -- Holiday flags (is_business_day_bw) are derived from hol_name
        -- in combined — holiday logic only needs to be written once.
        CASE
            -- Fixed holidays
            WHEN c.month_int = 1  AND c.day_int = 1  THEN 'Neujahr'
            WHEN c.month_int = 1  AND c.day_int = 6  THEN 'Heilige Drei Könige'
            WHEN c.month_int = 5  AND c.day_int = 1  THEN 'Tag der Arbeit'
            WHEN c.month_int = 10 AND c.day_int = 3  THEN 'Tag der Deutschen Einheit'
            WHEN c.month_int = 11 AND c.day_int = 1  THEN 'Allerheiligen'
            WHEN c.month_int = 12 AND c.day_int = 25 THEN '1. Weihnachtsfeiertag'
            WHEN c.month_int = 12 AND c.day_int = 26 THEN '2. Weihnachtsfeiertag'
            -- Easter-dependent holidays
            WHEN c.date = DATEADD(day, -2, e.easter_date) THEN 'Karfreitag'
            WHEN c.date = e.easter_date                    THEN 'Ostersonntag'
            WHEN c.date = DATEADD(day,  1, e.easter_date) THEN 'Ostermontag'
            WHEN c.date = DATEADD(day, 39, e.easter_date) THEN 'Christi Himmelfahrt'
            WHEN c.date = DATEADD(day, 49, e.easter_date) THEN 'Pfingstsonntag'
            WHEN c.date = DATEADD(day, 50, e.easter_date) THEN 'Pfingstmontag'
            WHEN c.date = DATEADD(day, 60, e.easter_date) THEN 'Fronleichnam'
            ELSE NULL
        END AS hol_name
    FROM dates c
    LEFT JOIN easter_dates e ON c.year_int = e.year_int
),

-- ── Final assembly ────────────────────────────────────────────────────────────
-- Joins date flags with holiday data. is_business_day_bw is named here so that
-- business_days_bw (integer) can be derived from it without repeating the condition.
combined AS (
    SELECT
        c.*,
        h.hol_name                                          AS hol_name_bw,
        h.hol_name IS NOT NULL                              AS is_hol_bw,
        h.hol_name IS NULL AND NOT c.is_weekend             AS is_business_day_bw,
        -- UTC offset for reference (use CONVERT_TIMEZONE for calculations)
        CASE
            WHEN c.date >=
                DATEADD(day,
                -MOD(EXTRACT(dayofweek_iso FROM TO_DATE(YEAR(c.date) || '-03-31')), 7),
                TO_DATE(YEAR(c.date) || '-03-31'))    -- last Sunday in March
            AND c.date <
                DATEADD(day,
                -MOD(EXTRACT(dayofweek_iso FROM TO_DATE(YEAR(c.date) || '-10-31')), 7),
                TO_DATE(YEAR(c.date) || '-10-31'))    -- last Sunday in October
            THEN 2  -- CEST (Summer Time, UTC+2)
            ELSE 1  -- CET  (Winter Time, UTC+1)
        END AS utc_offset
    FROM dates c
    LEFT JOIN bw_holidays h ON c.date = h.date
)

SELECT
    *,
    is_business_day_bw::INT AS business_days_bw    -- 1 = business day; SUM() to count business days in any period
FROM combined
ORDER BY date;
