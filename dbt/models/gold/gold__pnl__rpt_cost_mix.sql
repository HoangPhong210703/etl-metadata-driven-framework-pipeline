{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_cost_mix — Cost breakdown by category
    Powers: Cost Percentage pie/donut chart

    Placeholder metrics (need real source data):
      - member_salary     → needs: timesheet proration (salary × days_worked/working_days)
      - member_overtime   → needs: overtime hours from timesheet
      Extend with more cost categories as sources become available:
        project_bonus, infra_cost, tool_license, subcontractor, etc.
#}

with cost_by_category as (

    select
        d.year,
        d.month,
        make_date(d.year, d.month, 1)      as month_date,
        c.cost_category_key,
        cc.cost_category,
        cc.cost_group,
        sum(c.cost_actual)                  as cost_actual,
        sum(c.cost_forecast)                as cost_forecast
    from {{ ref('gold__pnl__fct_cost_monthly') }} c
    inner join {{ ref('gold__common__dim_date') }} d
        on c.date_key = d.date_key
    left join {{ ref('gold__pnl__dim_cost_category') }} cc
        on c.cost_category_key = cc.cost_category_key
    group by d.year, d.month, c.cost_category_key, cc.cost_category, cc.cost_group

),

monthly_total as (

    select
        year,
        month,
        sum(cost_actual) as total_cost_actual
    from cost_by_category
    group by year, month

),

final as (

    select
        c.year,
        c.month,
        c.month_date,
        c.cost_category_key,
        c.cost_category,
        c.cost_group,
        c.cost_actual,
        c.cost_forecast,
        case
            when coalesce(mt.total_cost_actual, 0) > 0
            then c.cost_actual / mt.total_cost_actual
            else null
        end                                 as cost_pct

    from cost_by_category c
    left join monthly_total mt
        on c.year = mt.year and c.month = mt.month

)

select * from final
