{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_employee_performance — Employee performance summary and details
    Powers: Employee Performance module
    Grain: one row per (month, employee, project)

    Placeholder metrics:
      - effort_rate             → needs: tabProject User.effort_rate
      - performance_rate        → needs: tabProject User.performance_rate (0.1 - 0.3)
      - total_effort            → working_days × 8 × effort_rate
      - revenue_contribution    → avg_revenue_rate × effort_rate × performance_rate
      - cost_contribution       → direct_cost prorated by working days
      - profit_contribution     → revenue - cost per member
#}

with dim_date as (

    select distinct
        (year * 10000 + month * 100 + 1)    as date_key,
        make_date(year, month, 1)           as month_date,
        year,
        month,
        total_working_days_in_month
    from {{ ref('gold__common__dim_date') }}
    where is_working_day = true
      and make_date(year, month, 1) <= current_date

),

dim_employee as (

    select
        employee_key,
        employee_id,
        employee_name,
        department,
        employment_type,
        base_salary,
        _source
    from {{ ref('gold__pnl__dim_employee') }}

),

dim_project as (

    select
        project_key,
        project_id,
        project_name,
        project_type,
        _source
    from {{ ref('gold__pnl__dim_project') }}

),

-- Placeholder: when tabProject User and timesheet data are available,
-- replace this CTE with actual performance data
employee_performance as (

    select
        null::int           as date_key,
        null::text          as employee_key,
        null::text          as project_key,
        null::numeric       as effort_rate,
        null::numeric       as performance_rate,
        null::numeric       as total_effort_hours,
        null::numeric       as actual_hours,
        null::numeric       as revenue_contribution,
        null::numeric       as cost_contribution,
        null::numeric       as profit_contribution
    where false

),

final as (

    select
        d.month_date,
        d.year,
        d.month,
        de.employee_id,
        de.employee_name,
        de.department,
        de.employment_type,
        de.base_salary,
        dp.project_id,
        dp.project_name,
        dp.project_type,
        ep.effort_rate,
        ep.performance_rate,
        ep.total_effort_hours,
        ep.actual_hours,
        ep.revenue_contribution,
        ep.cost_contribution,
        ep.profit_contribution

    from employee_performance ep
    inner join dim_date d on ep.date_key = d.date_key
    left join dim_employee de on ep.employee_key = de.employee_key
    left join dim_project dp on ep.project_key = dp.project_key

)

select * from final
