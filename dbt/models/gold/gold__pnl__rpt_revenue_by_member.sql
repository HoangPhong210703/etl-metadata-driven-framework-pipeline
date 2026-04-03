{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_revenue_by_member — Revenue contribution per employee per project
    Powers: Revenue Details Report → Project revenue report by members
    Grain: one row per (month, employee, project)

    Placeholder metrics:
      - effort_days             → needs: tabProject User or timesheet
      - effort_hours            → needs: timesheet or tabProject User
      - performance_rate        → needs: tabProject User.performance_rate
      - employee_rate           → needs: project_contract_headcount.rate
      - revenue_actual          → for teambase: rate × actual hours
                                  for fix cost: (effort/total_effort) × performance_rate × monthly_revenue
      - revenue_forecast        → same formula with forecast hours/rates
#}

with dim_date as (

    select distinct
        (year * 10000 + month * 100 + 1)    as date_key,
        make_date(year, month, 1)           as month_date,
        year,
        month
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
        _source
    from {{ ref('gold__pnl__dim_employee') }}

),

dim_project as (

    select
        project_key,
        project_id,
        project_name,
        project_type,
        market,
        _source
    from {{ ref('gold__pnl__dim_project') }}

),

-- Placeholder: when timesheet or tabProject User data is available,
-- replace this CTE with actual employee-project-month allocation
member_project_allocation as (

    select
        null::int           as date_key,
        null::text          as employee_key,
        null::text          as project_key,
        null::numeric       as effort_days,
        null::numeric       as effort_hours,
        null::numeric       as performance_rate,
        null::numeric       as employee_rate,
        null::numeric       as revenue_actual,
        null::numeric       as revenue_forecast
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
        dp.project_id,
        dp.project_name,
        dp.project_type,
        dp.market,
        mpa.effort_days,
        mpa.effort_hours,
        mpa.performance_rate,
        mpa.employee_rate,
        mpa.revenue_actual,
        mpa.revenue_forecast

    from member_project_allocation mpa
    inner join dim_date d on mpa.date_key = d.date_key
    left join dim_employee de on mpa.employee_key = de.employee_key
    left join dim_project dp on mpa.project_key = dp.project_key

)

select * from final
