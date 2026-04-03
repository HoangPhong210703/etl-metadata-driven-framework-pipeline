{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_revenue_mix — Revenue breakdown by type
    Powers: Revenue Percentage pie/donut chart

    Placeholder metrics (need real source data):
      - teambase revenue  → needs: timesheet hours × billing rate
      - fix_cost revenue  → needs: contract value × completion rate
      Extend with more revenue types as sources become available.
#}

with revenue_by_type as (

    select
        d.year,
        d.month,
        make_date(d.year, d.month, 1)       as month_date,
        r.revenue_type,
        sum(r.revenue_actual)               as revenue_actual,
        sum(r.revenue_forecast)             as revenue_forecast
    from {{ ref('gold__pnl__fct_revenue_monthly') }} r
    inner join {{ ref('gold__common__dim_date') }} d
        on r.date_key = d.date_key
    group by d.year, d.month, r.revenue_type

),

monthly_total as (

    select
        year,
        month,
        sum(revenue_actual) as total_revenue_actual
    from revenue_by_type
    group by year, month

),

final as (

    select
        r.year,
        r.month,
        r.month_date,
        r.revenue_type,
        r.revenue_actual,
        r.revenue_forecast,
        case
            when coalesce(mt.total_revenue_actual, 0) > 0
            then r.revenue_actual / mt.total_revenue_actual
            else null
        end                                 as revenue_pct

    from revenue_by_type r
    left join monthly_total mt
        on r.year = mt.year and r.month = mt.month

)

select * from final
