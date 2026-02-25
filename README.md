# Calendar

A general-purpose Snowflake SQL calendar for Baden-Württemberg, Germany.

## Purpose

Generates one row per date covering 1 January five years ago to 31 December of the current year. Includes period flags for common analysis windows and public holiday logic for Baden-Württemberg.

## How to use

Copy `Calendar.sql` into any Snowflake query as a CTE or standalone select. Delete the period flag sections not required for the analysis at hand — each section is clearly marked with a comment header.

## Coverage

- **Geography:** Baden-Württemberg, Germany
- **Holidays:** Fixed and Easter-dependent public holidays
- **Period flags:** Year, quarter, month, rolling 12 months, week, day
- **Timezone:** UTC offset included for reference; use Snowflake's `CONVERT_TIMEZONE` for calculations

## Requirements

- Snowflake
