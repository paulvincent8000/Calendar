/* General Purpose Calendar – Baden-Württemberg with public holidays

   Date range: 1 January (current year minus 5) to 31 December (current year).

   Two reference dates drive all period calculations:
     ref_d  – yesterday (last closed day)
     ref_m  – last day of the prior month (last closed month)

   Daily flags (_D) anchor their upper bound to ref_d.
   Monthly flags (_M) and full-month windows anchor to ref_m.
   Full calendar period flags (_F) use CURRENT_DATE() as they are not
   sensitive to the open-day issue.

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
    TO_CHAR(date, 'YYYYMMDD')                           AS d,
    date,
    YEAR(date)                                          AS year_int,
    'Q' || QUARTER(date)                                AS quarter_of_year,
    CASE WHEN MONTH(date) <= 6 THEN 'H1' ELSE 'H2' END AS half,
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
    DATEDIFF('day',     date, CURRENT_DATE())           AS day_offset,
    DATEDIFF('week',    date, CURRENT_DATE())           AS week_offset,
    DATEDIFF('month',   date, CURRENT_DATE())           AS month_offset,
    DATEDIFF('quarter', date, CURRENT_DATE())           AS quarter_offset,
    DATEDIFF('year',    date, CURRENT_DATE())           AS year_offset,

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 02 · Current Period Flags
    -- _D: upper bound = ref_d (yesterday, last closed day)
    -- _M: upper bound = ref_m (last closed month-end)
    -- _F: full calendar period including future days within it
    -- ════════════════════════════════════════════════════════════════════════
    date >= DATE_TRUNC('year',    CURRENT_DATE())
        AND date <= r.ref_d                             AS is_ytd_d,       -- YTD daily: Jan 1 → ref_d
    date >= DATE_TRUNC('year',    CURRENT_DATE())
        AND date <= r.ref_m                             AS is_ytd_m,       -- YTD monthly: Jan 1 → ref_m
    date >= DATE_TRUNC('quarter', CURRENT_DATE())
        AND date <= r.ref_d                             AS is_qtd_d,       -- QTD daily: quarter start → ref_d
    date >= DATE_TRUNC('quarter', CURRENT_DATE())
        AND date <= r.ref_m                             AS is_qtd_m,       -- QTD monthly: quarter start → ref_m
    date >= DATE_TRUNC('month',   CURRENT_DATE())
        AND date <= r.ref_d                             AS is_mtd_d,       -- MTD daily: month start → ref_d
    YEAR(date)  = YEAR(CURRENT_DATE())
        AND MONTH(date) = MONTH(CURRENT_DATE())         AS is_cm_f,        -- Current Month (full calendar month)
    YEAR(date)    = YEAR(CURRENT_DATE())
        AND QUARTER(date) = QUARTER(CURRENT_DATE())     AS is_cq_f,        -- Current Quarter (full)
    YEAR(date) = YEAR(CURRENT_DATE())                   AS is_cy_f,        -- Current Year (full)
    date >= DATE_TRUNC('week', CURRENT_DATE())
        AND date <  DATEADD(week, 1,
            DATE_TRUNC('week', CURRENT_DATE()))         AS is_cw_f,        -- Current Week (full)
    date = CURRENT_DATE()                               AS is_today,

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 03 · Prior Period Flags — Like-for-Like
    -- Mirrors the current period shifted back by one year/quarter/month,
    -- clipped to the same elapsed days for apples-to-apples comparison.
    -- ════════════════════════════════════════════════════════════════════════
    date >= DATE_TRUNC('year', DATEADD(year, -1, CURRENT_DATE()))
        AND date <= DATEADD(year, -1, r.ref_d)          AS is_pytd_d,      -- Prior YTD daily: PY Jan 1 → (ref_d − 1 year)
    date >= DATE_TRUNC('year', DATEADD(year, -1, CURRENT_DATE()))
        AND date <= DATEADD(year, -1, r.ref_m)          AS is_pytd_m,      -- Prior YTD monthly: PY Jan 1 → (ref_m − 1 year)
    date >= DATE_TRUNC('quarter', DATEADD(month, -3, CURRENT_DATE()))
        AND date <= DATEADD(month, -3, r.ref_d)         AS is_pqtd_d,      -- Prior QTD daily: prior quarter start → (ref_d − 1 quarter)
    date >= DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE()))
        AND date <= DATEADD(month, -1, r.ref_d)         AS is_pmtd_d,      -- Prior MTD daily: prior month start → (ref_d − 1 month)

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 04 · Prior Period Flags — Full Reference
    -- Complete prior calendar periods used for benchmarks and trend lines
    -- ════════════════════════════════════════════════════════════════════════
    YEAR(date) = YEAR(CURRENT_DATE()) - 1               AS is_fpy,         -- Full Prior Year
    date >= DATE_TRUNC('quarter', r.ref_m)
        AND date <  DATE_TRUNC('quarter', CURRENT_DATE()) AS is_fpq,       -- Full Prior Quarter
    date >= DATE_TRUNC('month',   r.ref_m)
        AND date <= r.ref_m                             AS is_fpm,         -- Full Prior Month
    date >= DATE_TRUNC('week', DATEADD(week, -1, CURRENT_DATE()))
        AND date <  DATE_TRUNC('week', CURRENT_DATE())  AS is_fpw,         -- Full Prior Week
    date = r.ref_d                                      AS is_yesterday,

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 05 · Trailing Windows
    -- All windows are inclusive of ref_d as the last completed day.
    -- Use C_/P_ pairing for period-over-period comparisons.
    -- ════════════════════════════════════════════════════════════════════════
    date >= DATEADD(day,   -6, r.ref_d)
        AND date <= r.ref_d                             AS is_l7d,         -- Last 7 completed days
    date >= DATEADD(day,  -29, r.ref_d)
        AND date <= r.ref_d                             AS is_l30d,        -- Last 30 completed days
    date >= DATE_TRUNC('month', DATEADD(month, -12, CURRENT_DATE()))
        AND date <= r.ref_m                             AS c_l12m_f,       -- Last 12 full months (pair: P_L12M_F)
    date >= DATEADD(day, -364, r.ref_d)
        AND date <= r.ref_d                             AS is_ttm,         -- Trailing 12 months (rolling 365 completed days)
    date >= DATE_TRUNC('month', DATEADD(month, -24, CURRENT_DATE()))
        AND date <  DATE_TRUNC('month',
            DATEADD(month, -12, CURRENT_DATE()))        AS p_l12m_f,       -- Prior 12 full months (pair: C_L12M_F)

    -- ════════════════════════════════════════════════════════════════════════
    -- Group 06 · Attributes & Maturity
    -- ════════════════════════════════════════════════════════════════════════
    date <= r.ref_m                                     AS is_cmpl_m,      -- TRUE if the date falls in a fully elapsed month
    DAYOFYEAR(date)                                     AS doy,            -- Day of year (1–366)
    DAYOFWEEK(date) IN (0, 6)                           AS is_weekend

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
        -- Holiday flags (is_hol_bw, is_bday_bw) are derived from hol_name
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
-- Joins date flags with holiday data. is_bday_bw is named here so that
-- bday_bw (integer) can be derived from it in the outer SELECT without
-- repeating the condition. is_bday_bw references is_weekend from dates,
-- so the weekend check is defined in exactly one place.
combined AS (
    SELECT
        c.*,
        h.hol_name                                          AS hol_name_bw,
        h.hol_name IS NOT NULL                              AS is_hol_bw,
        h.hol_name IS NULL AND NOT c.is_weekend             AS is_bday_bw,
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
    is_bday_bw::INT AS bday_bw    -- 1 = business day; SUM() to count business days in any period
FROM combined
ORDER BY date;
