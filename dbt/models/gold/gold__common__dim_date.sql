{{ config(
    materialized='table',
    schema='gold__common'
) }}

with date_spine as (

    select
        d::date as date_actual
    from generate_series('2020-01-01'::date, '2030-12-31'::date, '1 day'::interval) as d

),

holidays as (

    select distinct
        holiday_date::date as holiday_date
    from {{ ref('silver__project__tab_holiday') }}
    where holiday_date is not null

),

base_calendar as (

    select
        ds.date_actual,
        extract(year from ds.date_actual)::int                          as year,
        extract(quarter from ds.date_actual)::int                       as quarter,
        extract(month from ds.date_actual)::int                         as month,
        to_char(ds.date_actual, 'FMMonth')                              as month_name,
        extract(isodow from ds.date_actual)::int                        as day_of_week,
        to_char(ds.date_actual, 'FMDay')                                as day_name,
        extract(isodow from ds.date_actual)::int in (6, 7)             as is_weekend,
        h.holiday_date is not null                                      as is_holiday,
        not (extract(isodow from ds.date_actual)::int in (6, 7))
            and h.holiday_date is null                                  as is_working_day
    from date_spine ds
    left join holidays h on ds.date_actual = h.holiday_date

),

with_working_day_numbers as (

    select
        *,
        case
            when is_working_day then
                row_number() over (
                    partition by year, month, is_working_day
                    order by date_actual
                )
            else null
        end as working_day_of_month,
        sum(case when is_working_day then 1 else 0 end) over (
            partition by year, month
        ) as total_working_days_in_month
    from base_calendar

),

final as (

    select
        to_char(date_actual, 'YYYYMMDD')::int                          as date_key,
        date_actual,
        year,
        quarter,
        month,
        month_name,
        day_of_week,
        day_name,
        is_weekend,
        is_holiday,
        is_working_day,
        working_day_of_month,
        total_working_days_in_month,
        date_trunc('month', date_actual)::date                          as month_start_date,
        (date_trunc('month', date_actual) + interval '1 month - 1 day')::date as month_end_date,
        date_trunc('quarter', date_actual)::date                        as quarter_start_date,
        year                                                            as fiscal_year,
        quarter                                                         as fiscal_quarter
    from with_working_day_numbers

)

select * from final
