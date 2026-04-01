{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    fct_headcount_monthly — Monthly headcount snapshot for KPIs
    Grain: one row per (month, employee)
    Derived KPIs:
      - Billable Rate = SUM(is_billable) / SUM(is_active)
      - Busy Rate = SUM(is_billable OR is_hr_project) / SUM(is_active)
      - Available HC = SUM(is_pool)
      - Dev Avg Salary = SUM(total_salary) / SUM(is_active)
#}

with dim_date as (

    select distinct
        year,
        month,
        (year * 10000 + month * 100 + 1) as date_key,
        total_working_days_in_month
    from {{ ref('gold__common__dim_date') }}
    where is_working_day = true

),

dim_employee as (

    select
        employee_key,
        employee_id,
        employee_name,
        base_salary,
        billing_rate,
        employment_type,
        _source
    from {{ ref('gold__pnl__dim_employee') }}

),

dim_project as (

    select project_key, project_id, project_name, _source
    from {{ ref('gold__pnl__dim_project') }}

),

dim_organization as (

    select org_key, department_code, _source
    from {{ ref('gold__pnl__dim_organization') }}

),

-- Employees active in each month
-- Placeholder: requires a project-level daily timesheet source (not yet available)
monthly_activity as (

    select
        null::int       as year,
        null::int       as month,
        null::text      as employee_key,
        null::text      as org_key,
        null::boolean   as has_billable_work,
        null::numeric   as total_hours
    where false

),

-- Detect special project assignments per employee per month
-- Placeholder: requires timesheet source
project_assignments as (

    select
        null::int       as year,
        null::int       as month,
        null::text      as employee_key,
        null::text      as project_name,
        null::numeric   as hours_on_project
    where false

),

-- Flag special project types per employee per month
special_flags as (

    select
        year,
        month,
        employee_key,
        bool_or(lower(project_name) like '%hr%'
            or lower(project_name) like '%interview%')
                                        as is_hr_project,
        bool_or(lower(project_name) like '%pool%')
                                        as is_pool,
        bool_or(lower(project_name) like '%training%'
            or lower(project_name) like '%resource pool%')
                                        as is_training
    from project_assignments
    group by year, month, employee_key

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'dd.date_key', 'de.employee_key'
        ]) }}                           as headcount_monthly_key,
        dd.date_key,
        de.employee_key,
        ma.org_key,
        true                            as is_active,
        ma.has_billable_work            as is_billable,
        coalesce(sf.is_hr_project, false) as is_hr_project,
        coalesce(sf.is_pool, false)     as is_pool,
        coalesce(sf.is_training, false) as is_training,
        de.base_salary                  as total_salary,
        de.billing_rate,
        case
            when de.employment_type = 'Part-time' then 0.5
            else 1.0
        end                             as headcount_value
    from monthly_activity ma
    inner join dim_date dd
        on ma.year = dd.year and ma.month = dd.month
    inner join dim_employee de
        on ma.employee_key = de.employee_key
    left join special_flags sf
        on ma.year = sf.year
        and ma.month = sf.month
        and ma.employee_key = sf.employee_key

)

select * from final
