{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    fct_revenue_monthly — Revenue by project per month
    Grain: one row per (month, project)
    Revenue types:
      - Teambase: rate x hours (from timesheet aggregation)
      - Fix Cost: contract x completion rate (placeholder CTEs for missing custom tables)
#}

with dim_date as (

    select
        date_key,
        date_actual,
        year,
        month,
        month_start_date,
        total_working_days_in_month
    from {{ ref('gold__common__dim_date') }}
    where date_actual = month_start_date  -- one row per month

),

dim_project as (

    select
        project_key,
        project_id,
        project_name,
        project_type,
        total_sales_amount,
        gross_margin,
        plan_complete_rate,
        actual_complete_rate,
        _source
    from {{ ref('gold__pnl__dim_project') }}

),

dim_organization as (

    select org_key, department_code, _source
    from {{ ref('gold__pnl__dim_organization') }}

),

{#
    Teambase revenue — skipped for now
    Requires a project-level daily timesheet source (not yet available).
    When available, add timesheet_monthly CTE + teambase_revenue CTE here.

    Fix Cost revenue — placeholder
    When projects_contract, fixcost_delivery_plan, project_contract_headcount,
    and fixcost_project_package tables become available, replace these CTEs.
    Formula: contract_revenue x completion_rate
#}
fixcost_revenue as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'dd.date_key', 'dp.project_key'
        ]) }}                           as revenue_monthly_key,
        dd.date_key,
        dp.project_key,
        null                            as org_key,
        'fix_cost'                      as revenue_type,
        dp.total_sales_amount           as contract_revenue,
        dp.plan_complete_rate           as complete_rate_plan,
        dp.actual_complete_rate         as complete_rate_actual,
        null::numeric                   as headcount_rate,
        null::numeric                   as total_hours_forecast,
        null::numeric                   as total_hours_actual,
        -- Forecast: contract x plan completion rate
        dp.total_sales_amount * dp.plan_complete_rate
                                        as revenue_forecast,
        -- Actual: contract x actual completion rate
        dp.total_sales_amount * dp.actual_complete_rate
                                        as revenue_actual
    from dim_project dp
    cross join dim_date dd
    where dp.project_type = 'Fix Cost'
      and dp.total_sales_amount is not null

),

final as (

    select * from fixcost_revenue

)

select * from final
