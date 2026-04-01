{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    fct_cost_monthly — Cost allocations per month
    Grain: one row per (month, employee, project, cost_category)
    Sources: tabEmployment Contract (salary), adjusted_attendance_register (days worked),
             savvycom_project_project_member (project assignments)
#}

with dim_date as (

    select
        date_key,
        date_actual,
        year,
        month,
        month_start_date,
        total_working_days_in_month,
        is_working_day
    from {{ ref('gold__common__dim_date') }}

),

dim_employee as (

    select employee_key, employee_id, base_salary, _source
    from {{ ref('gold__pnl__dim_employee') }}

),

dim_project as (

    select project_key, project_id, _source
    from {{ ref('gold__pnl__dim_project') }}

),

dim_organization as (

    select org_key, department_code, _source
    from {{ ref('gold__pnl__dim_organization') }}

),

-- Monthly working days from dim_date (one row per month)
monthly_working_days as (

    select distinct
        year,
        month,
        (year * 10000 + month * 100 + 1) as date_key,
        total_working_days_in_month
    from dim_date
    where is_working_day = true

),

-- Days worked per employee per project per month
-- Placeholder: requires a project-level daily timesheet source (not yet available)
employee_project_monthly as (

    select
        null::int       as year,
        null::int       as month,
        null::text      as employee_key,
        null::text      as project_key,
        null::text      as org_key,
        null::int       as days_worked,
        null::numeric   as total_hours,
        null::numeric   as total_overtime_hours
    where false

),

-- Member Salary: prorated by working days
salary_cost as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'mwd.date_key', 'epm.employee_key', 'epm.project_key',
            "'member_salary'"
        ]) }}                           as cost_monthly_key,
        mwd.date_key,
        epm.employee_key,
        epm.project_key,
        epm.org_key,
        'member_salary'                 as cost_category_key,
        mwd.total_working_days_in_month as working_days_in_month,
        epm.days_worked,
        de.base_salary,
        de.base_salary * (epm.days_worked::numeric
            / nullif(mwd.total_working_days_in_month, 0))
                                        as prorated_salary,
        null::numeric                   as project_bonus,
        null::numeric                   as overtime_cost,
        de.base_salary * (epm.days_worked::numeric
            / nullif(mwd.total_working_days_in_month, 0))
                                        as cost_actual,
        de.base_salary                  as cost_forecast
    from employee_project_monthly epm
    inner join monthly_working_days mwd
        on epm.year = mwd.year and epm.month = mwd.month
    inner join dim_employee de
        on epm.employee_key = de.employee_key
    where de.base_salary is not null

),

-- Overtime cost
overtime_cost as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'mwd.date_key', 'epm.employee_key', 'epm.project_key',
            "'member_overtime'"
        ]) }}                           as cost_monthly_key,
        mwd.date_key,
        epm.employee_key,
        epm.project_key,
        epm.org_key,
        'member_overtime'               as cost_category_key,
        mwd.total_working_days_in_month as working_days_in_month,
        epm.days_worked,
        de.base_salary,
        null::numeric                   as prorated_salary,
        null::numeric                   as project_bonus,
        -- OT cost = (salary / working_days / 8 hours) * 1.5 * OT hours
        (de.base_salary
            / nullif(mwd.total_working_days_in_month * 8, 0))
            * 1.5 * epm.total_overtime_hours
                                        as overtime_cost,
        (de.base_salary
            / nullif(mwd.total_working_days_in_month * 8, 0))
            * 1.5 * epm.total_overtime_hours
                                        as cost_actual,
        null::numeric                   as cost_forecast
    from employee_project_monthly epm
    inner join monthly_working_days mwd
        on epm.year = mwd.year and epm.month = mwd.month
    inner join dim_employee de
        on epm.employee_key = de.employee_key
    where epm.total_overtime_hours > 0
      and de.base_salary is not null

),

final as (

    select * from salary_cost
    union all
    select * from overtime_cost

)

select * from final
