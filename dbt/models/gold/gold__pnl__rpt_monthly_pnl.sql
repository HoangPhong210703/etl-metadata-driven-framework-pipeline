{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_monthly_pnl — Monthly P&L summary
    Powers: Revenue KPI, P&L KPI, Total Revenue by Month, P&L by Month

    Placeholder metrics (need real source data):
      - total_revenue_teambase    → needs: timesheet hours × billing rate
      - total_revenue_fixcost     → needs: contract value × completion rate
      - total_cost_salary         → needs: timesheet hours per project for proration
      - total_cost_overtime       → needs: overtime hours from timesheet
      - total_cost_other          → needs: other cost sources (infra, tools, etc.)
#}

with months as (

    select distinct
        year,
        month,
        (year * 10000 + month * 100 + 1)   as date_key,
        make_date(year, month, 1)           as month_date,
        total_working_days_in_month
    from {{ ref('gold__common__dim_date') }}
    where is_working_day = true
      and make_date(year, month, 1) <= current_date

),

revenue_agg as (

    select
        r.date_key,
        coalesce(sum(r.revenue_actual)  filter (where r.revenue_type = 'teambase'), 0)  as revenue_teambase_actual,
        coalesce(sum(r.revenue_forecast) filter (where r.revenue_type = 'teambase'), 0) as revenue_teambase_forecast,
        coalesce(sum(r.revenue_actual)  filter (where r.revenue_type = 'fix_cost'), 0)  as revenue_fixcost_actual,
        coalesce(sum(r.revenue_forecast) filter (where r.revenue_type = 'fix_cost'), 0) as revenue_fixcost_forecast
    from {{ ref('gold__pnl__fct_revenue_monthly') }} r
    group by r.date_key

),

cost_agg as (

    select
        c.date_key,
        coalesce(sum(c.cost_actual)  filter (where c.cost_category_key = 'member_salary'), 0)   as cost_salary_actual,
        coalesce(sum(c.cost_forecast) filter (where c.cost_category_key = 'member_salary'), 0)  as cost_salary_forecast,
        coalesce(sum(c.cost_actual)  filter (where c.cost_category_key = 'member_overtime'), 0) as cost_overtime_actual,
        coalesce(sum(c.cost_actual), 0)   as cost_total_actual,
        coalesce(sum(c.cost_forecast), 0) as cost_total_forecast
    from {{ ref('gold__pnl__fct_cost_monthly') }} c
    group by c.date_key

),

final as (

    select
        m.date_key,
        m.month_date,
        m.year,
        m.month,
        m.total_working_days_in_month,

        -- Revenue breakdown
        coalesce(ra.revenue_teambase_actual, 0)     as revenue_teambase_actual,
        coalesce(ra.revenue_teambase_forecast, 0)   as revenue_teambase_forecast,
        coalesce(ra.revenue_fixcost_actual, 0)      as revenue_fixcost_actual,
        coalesce(ra.revenue_fixcost_forecast, 0)    as revenue_fixcost_forecast,

        -- Total revenue
        coalesce(ra.revenue_teambase_actual, 0)
            + coalesce(ra.revenue_fixcost_actual, 0)    as total_revenue_actual,
        coalesce(ra.revenue_teambase_forecast, 0)
            + coalesce(ra.revenue_fixcost_forecast, 0)  as total_revenue_forecast,

        -- Cost breakdown
        coalesce(ca.cost_salary_actual, 0)          as cost_salary_actual,
        coalesce(ca.cost_salary_forecast, 0)        as cost_salary_forecast,
        coalesce(ca.cost_overtime_actual, 0)        as cost_overtime_actual,
        coalesce(ca.cost_total_actual, 0)           as total_cost_actual,
        coalesce(ca.cost_total_forecast, 0)         as total_cost_forecast,

        -- P&L
        (coalesce(ra.revenue_teambase_actual, 0) + coalesce(ra.revenue_fixcost_actual, 0))
            - coalesce(ca.cost_total_actual, 0)     as gross_profit_actual,
        (coalesce(ra.revenue_teambase_forecast, 0) + coalesce(ra.revenue_fixcost_forecast, 0))
            - coalesce(ca.cost_total_forecast, 0)   as gross_profit_forecast,

        -- Margin %
        case
            when (coalesce(ra.revenue_teambase_actual, 0) + coalesce(ra.revenue_fixcost_actual, 0)) > 0
            then ((coalesce(ra.revenue_teambase_actual, 0) + coalesce(ra.revenue_fixcost_actual, 0))
                  - coalesce(ca.cost_total_actual, 0))
                 / (coalesce(ra.revenue_teambase_actual, 0) + coalesce(ra.revenue_fixcost_actual, 0))
            else null
        end                                         as gross_margin_pct

    from months m
    left join revenue_agg ra on m.date_key = ra.date_key
    left join cost_agg ca on m.date_key = ca.date_key

)

select * from final
