{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_rate_metrics — Monthly headcount rate KPIs
    Powers: Busy Rate widget, Billable Rate widget

    Placeholder metrics (need real source data):
      - billable_rate    → needs: fct_headcount_monthly.is_billable (requires timesheet)
      - busy_rate        → needs: fct_headcount_monthly.is_billable + is_hr_project (requires timesheet)
      - available_hc     → needs: fct_headcount_monthly.is_pool (requires timesheet)
      - avg_salary       → needs: fct_headcount_monthly.total_salary / active count
#}

with headcount as (

    select
        date_key,
        count(*)                                                    as total_headcount,
        sum(headcount_value)                                        as total_hc_value,
        count(*) filter (where is_billable = true)                  as billable_count,
        count(*) filter (where is_billable = true or is_hr_project = true)
                                                                    as busy_count,
        count(*) filter (where is_pool = true)                      as available_pool,
        count(*) filter (where is_training = true)                  as training_count,
        avg(total_salary)                                           as avg_salary,
        sum(total_salary)                                           as total_salary_cost
    from {{ ref('gold__pnl__fct_headcount_monthly') }}
    where is_active = true
    group by date_key

),

months as (

    select distinct
        (year * 10000 + month * 100 + 1)    as date_key,
        make_date(year, month, 1)           as month_date,
        year,
        month
    from {{ ref('gold__common__dim_date') }}
    where is_working_day = true
      and make_date(year, month, 1) <= current_date

),

final as (

    select
        m.date_key,
        m.month_date,
        m.year,
        m.month,

        coalesce(h.total_headcount, 0)      as total_headcount,
        coalesce(h.total_hc_value, 0)       as total_hc_value,
        coalesce(h.billable_count, 0)       as billable_count,
        coalesce(h.busy_count, 0)           as busy_count,
        coalesce(h.available_pool, 0)       as available_pool,
        coalesce(h.training_count, 0)       as training_count,

        -- KPI rates
        case
            when coalesce(h.total_headcount, 0) > 0
            then h.billable_count::numeric / h.total_headcount
            else null
        end                                 as billable_rate,

        case
            when coalesce(h.total_headcount, 0) > 0
            then h.busy_count::numeric / h.total_headcount
            else null
        end                                 as busy_rate,

        h.avg_salary                        as avg_salary,
        coalesce(h.total_salary_cost, 0)    as total_salary_cost

    from months m
    left join headcount h on m.date_key = h.date_key

)

select * from final
