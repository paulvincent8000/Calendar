/* General Purpose Calendar – Baden-Württemberg with public holidays

   Date range: 1 January (current year minus 5) to 31 December (current year).

   Analysis period flags are grouped near the top of the dates CTE.
   Holiday and business day flags appear lower in the query.

   Usage: copy the full query and delete the flag sections not required.
*/

WITH

-- ── Date generation ──────────────────────────────────────────────────────────
-- ROWCOUNT => 2200 is a sufficient ceiling for a ~6-year window.
-- The WHERE clause in calendar_base trims to the actual date range.
date_scaffold AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS day_offset
    FROM TABLE(GENERATOR(ROWCOUNT => 2200))
),

-- 1 January five years ago to 31 December of the current year
calendar_base AS (
    SELECT
        DATEADD(day, day_offset, DATE_TRUNC('year', DATEADD(year, -5, CURRENT_DATE()))) AS date
    FROM date_scaffold
    WHERE DATEADD(day, day_offset, DATE_TRUNC('year', DATEADD(year, -5, CURRENT_DATE())))
        < DATE_TRUNC('year', DATEADD(year, 1, CURRENT_DATE()))
),

dates AS (
    SELECT

    -- ════════════════════════════════════════════════════════════════════════
    -- Core date fields (required — do not delete)
    -- ════════════════════════════════════════════════════════════════════════
    TO_CHAR(date, 'YYYYMMDD')                           AS d,
    date,
    YEAR(date)                                          AS year_int,
    'Q' || QUARTER(date)                                AS quarter_of_year,
    CASE WHEN MONTH(date) <= 6 THEN 'H1' ELSE 'H2' END AS half,
    MONTHNAME(date)                                     AS month_name,
    TO_CHAR(date, 'MON')                                AS month_name_short,
    WEEKOFYEAR(date)                                    AS week_of_year,
    DATE_TRUNC('week', date)                            AS week_start_date,
    DATEADD(day, 6, DATE_TRUNC('week', date))           AS week_end_date,
    DAYNAME(date)                                       AS day_of_week_name,
    TO_CHAR(date, 'DY')                                 AS day_of_week_name_short,
    DAYOFWEEK(date)                                     AS day_of_week,   -- 0 = Sunday, 6 = Saturday
    MONTH(date)                                         AS month_int,
    DAY(date)                                           AS day_int,

    -- ════════════════════════════════════════════════════════════════════════
    -- Relative position to today
    -- Positive = past, negative = future, 0 = current week / month
    -- ════════════════════════════════════════════════════════════════════════
    DATEDIFF('week',  date, CURRENT_DATE())             AS weeks_from_today,
    DATEDIFF('month', date, CURRENT_DATE())             AS months_from_today,

    -- ════════════════════════════════════════════════════════════════════════
    -- Period flags: Year
    -- ════════════════════════════════════════════════════════════════════════
    YEAR(date) = YEAR(CURRENT_DATE())                   AS is_current_year,
    YEAR(date) = YEAR(CURRENT_DATE()) - 1               AS is_last_year,

    -- ════════════════════════════════════════════════════════════════════════
    -- Period flags: Quarter
    -- ════════════════════════════════════════════════════════════════════════
    YEAR(date)    = YEAR(CURRENT_DATE())
        AND QUARTER(date) = QUARTER(CURRENT_DATE())     AS is_current_quarter,
    date >= DATE_TRUNC('quarter', DATEADD(month, -3, CURRENT_DATE()))
        AND date <  DATE_TRUNC('quarter', CURRENT_DATE()) AS is_last_quarter,

    -- ════════════════════════════════════════════════════════════════════════
    -- Period flags: Month
    -- ════════════════════════════════════════════════════════════════════════
    YEAR(date)  = YEAR(CURRENT_DATE())
        AND MONTH(date) = MONTH(CURRENT_DATE())         AS is_current_month,
    date >= DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE()))
        AND date <  DATE_TRUNC('month', CURRENT_DATE()) AS is_last_month,

    -- ════════════════════════════════════════════════════════════════════════
    -- Period flags: Rolling 12 months
    -- Both periods exclude the current (incomplete) month.
    -- is_rolling_12m:       the 12 complete months ending at close of last month.
    -- is_prior_rolling_12m: the 12 complete months immediately before that.
    -- The two periods are mutually exclusive and together span 24 months.
    -- ════════════════════════════════════════════════════════════════════════
    date >= DATE_TRUNC('month', DATEADD(month, -12, CURRENT_DATE()))
        AND date <  DATE_TRUNC('month', CURRENT_DATE())                        AS is_rolling_12m,
    date >= DATE_TRUNC('month', DATEADD(month, -24, CURRENT_DATE()))
        AND date <  DATE_TRUNC('month', DATEADD(month, -12, CURRENT_DATE()))   AS is_prior_rolling_12m,

    -- ════════════════════════════════════════════════════════════════════════
    -- Period flags: Week
    -- ════════════════════════════════════════════════════════════════════════
    date >= DATE_TRUNC('week', CURRENT_DATE())
        AND date <  DATEADD(week, 1, DATE_TRUNC('week', CURRENT_DATE()))       AS is_current_week,
    date >= DATE_TRUNC('week', DATEADD(week, -1, CURRENT_DATE()))
        AND date <  DATE_TRUNC('week', CURRENT_DATE())                         AS is_last_week,

    -- ════════════════════════════════════════════════════════════════════════
    -- Period flags: Day
    -- ════════════════════════════════════════════════════════════════════════
    date = CURRENT_DATE()                               AS is_today,
    date = DATEADD(day, -1, CURRENT_DATE())             AS is_yesterday

    FROM calendar_base
),

-- ════════════════════════════════════════════════════════════════════════════
-- Holiday logic – Baden-Württemberg
-- ════════════════════════════════════════════════════════════════════════════

-- Easter Sunday calculated using the Meeus/Jones/Butcher algorithm
easter_dates AS (
    SELECT DISTINCT
        year_int,
        DATEADD(day,
            ((19 * (year_int % 19) + 24) % 30) +
            ((2 * (year_int % 4) + 4 * (year_int % 7) + 6 * ((19 * (year_int % 19) + 24) % 30) + 5) % 7) - 9,
        DATEADD(day,
            CASE WHEN ((19 * (year_int % 19) + 24) % 30) + ((2 * (year_int % 4) + 4 * (year_int % 7) + 6 * ((19 * (year_int % 19) + 24) % 30) + 5) % 7) > 9
            THEN 0 ELSE -31 END,
        TO_DATE(year_int || '-04-01', 'YYYY-MM-DD')
        )
        ) AS easter_date
    FROM dates
),

bw_holidays AS (
    SELECT
        c.date,

        -- Holiday name (NULL for non-holidays)
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
        END AS holiday_name,

        -- Public holiday flag (TRUE on named holidays, excluding Easter/Whit Sunday
        -- which are already Sundays and excluded by the weekend check below)
        CASE
            WHEN (c.month_int = 1  AND c.day_int = 1)
              OR (c.month_int = 1  AND c.day_int = 6)
              OR (c.month_int = 5  AND c.day_int = 1)
              OR (c.month_int = 10 AND c.day_int = 3)
              OR (c.month_int = 11 AND c.day_int = 1)
              OR (c.month_int = 12 AND c.day_int = 25)
              OR (c.month_int = 12 AND c.day_int = 26)
              OR c.date = DATEADD(day, -2, e.easter_date)
              OR c.date = DATEADD(day,  1, e.easter_date)
              OR c.date = DATEADD(day, 39, e.easter_date)
              OR c.date = DATEADD(day, 50, e.easter_date)
              OR c.date = DATEADD(day, 60, e.easter_date)
            THEN TRUE
            ELSE FALSE
        END AS is_public_holiday_bw,

        -- Business day flag: weekday that is not a public holiday
        CASE
            WHEN c.day_of_week IN (0, 6)                              -- Weekend
              OR (c.month_int = 1  AND c.day_int = 1)
              OR (c.month_int = 1  AND c.day_int = 6)
              OR (c.month_int = 5  AND c.day_int = 1)
              OR (c.month_int = 10 AND c.day_int = 3)
              OR (c.month_int = 11 AND c.day_int = 1)
              OR (c.month_int = 12 AND c.day_int = 25)
              OR (c.month_int = 12 AND c.day_int = 26)
              OR c.date = DATEADD(day, -2, e.easter_date)
              OR c.date = DATEADD(day,  1, e.easter_date)
              OR c.date = DATEADD(day, 39, e.easter_date)
              OR c.date = DATEADD(day, 50, e.easter_date)
              OR c.date = DATEADD(day, 60, e.easter_date)
            THEN FALSE
            ELSE TRUE
        END AS is_business_day_bw

    FROM dates c
    LEFT JOIN easter_dates e ON c.year_int = e.year_int
)

-- Final select
SELECT
    c.*,
    h.holiday_name       AS holiday_name_bw,
    h.is_public_holiday_bw,
    h.is_business_day_bw,
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
ORDER BY c.date;


/* Users with FTE */

WITH

UserData AS (
    SELECT
        $1 AS RocheUserLogin,
        $2 AS FTE
    FROM VALUES
        ('liverai', 1.0),
        ('nastaa1', 1.0),
        ('thiela7', 1.0),
        ('amjahads', 1.0),
        ('kattermv', 0.6),
        ('seredium', 1.0)
)

SELECT * FROM USERDATA
;

/* Validation */

SELECT
    DATE_TRUNC('month', DATE_FROM) AS DATUM,
    COUNT(DISTINCT case_id)        AS CASES,
    SUM(duration_in_minutes)/60    AS DURATION_IN_HOURS,
    DURATION_IN_HOURS / CASES      AS HOURS_PER_CASE
FROM srva_prod.dp_srva_pkpi_rexis.case_history
WHERE YEAR(date_from) >= 2025
  AND new_value = 'DE - Service - Dispatch Queue'
  AND sales_organization_code = 4519
GROUP BY 1
ORDER BY 1
LIMIT 1000;
