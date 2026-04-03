{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_revenue_by_project — Revenue detail by project, groupable by division/market/type
    Powers: Revenue Details Report → Revenue by project
    Grain: one row per (month, project)

    Placeholder metrics:
      - revenue_actual      → from fct_revenue_monthly (fix cost works, teambase placeholder)
      - revenue_forecast    → from fct_revenue_monthly
      - contract_revenue    → from dim_project.total_sales_amount
      - complete_rate_plan  → from fct_revenue_monthly
      - complete_rate_actual → from fct_revenue_monthly
      - headcount           → placeholder: needs project member count
#}

with revenue as (

    select
        r.date_key,
        r.project_key,
        r.revenue_type,
        r.contract_revenue,
        r.complete_rate_plan,
        r.complete_rate_actual,
        r.headcount_rate,
        r.total_hours_forecast,
        r.total_hours_actual,
        r.revenue_forecast,
        r.revenue_actual
    from {{ ref('gold__pnl__fct_revenue_monthly') }} r

),

dim_date as (

    select distinct
        (year * 10000 + month * 100 + 1)    as date_key,
        make_date(year, month, 1)           as month_date,
        year,
        month
    from {{ ref('gold__common__dim_date') }}
    where is_working_day = true

),

dim_project as (

    select
        project_key,
        project_id,
        project_name,
        project_type,
        market,
        total_sales_amount,
        _source
    from {{ ref('gold__pnl__dim_project') }}

),

final as (

    select
        d.month_date,
        d.year,
        d.month,
        dp.project_id,
        dp.project_name,
        dp.project_type,
        dp.market,
        null                                as division,            -- placeholder: needs project→division mapping
        dp._source,
        r.revenue_type,
        r.contract_revenue,
        r.complete_rate_plan,
        r.complete_rate_actual,
        r.headcount_rate,
        r.total_hours_forecast,
        r.total_hours_actual,
        r.revenue_forecast,
        r.revenue_actual,
        null::int                           as headcount            -- placeholder: needs project member count

    from revenue r
    inner join dim_date d on r.date_key = d.date_key
    inner join dim_project dp on r.project_key = dp.project_key

)

select * from final
