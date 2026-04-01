{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    dim_employee — Employee / Resource dimension for PnL
    Grain: one row per employee
    Sources: hr_employee (Odoo timesheet), tabEmployee + tabEmployment Contract (ERPNext)
#}

with odoo_employees as (

    select
        id::text                        as employee_id,
        name                            as employee_name,
        department_id,
        company_id,
        work_email,
        active,
        'postgres_timesheet'            as _source
    from {{ ref('silver__accounting__hr_employee') }}

),

erpnext_employees as (

    select
        name                            as employee_id,
        employee_name,
        department,
        designation,
        company,
        employment_type,
        status,
        'maria_erp'                     as _source
    from {{ ref('silver__project__tab_employee') }}

),

-- Latest employment contract per employee for salary info
erpnext_contracts as (

    select distinct on (employee)
        employee                        as employee_id,
        base_salary,
        company,
        designation
    from {{ ref('silver__project__tab_employment_contract') }}
    where docstatus = 1
    order by employee, modified desc

),

-- Odoo employees (no salary in Odoo — comes from ERPNext contracts)
from_odoo as (

    select
        {{ dbt_utils.generate_surrogate_key(['e.employee_id', 'e._source']) }} as employee_key,
        e.employee_id,
        e.employee_name,
        null                            as department,
        null                            as division,
        null                            as employment_type,
        null::numeric                   as base_salary,
        null::numeric                   as billing_rate,
        null                            as cost_center,
        'postgres_timesheet'            as _source
    from odoo_employees e

),

-- ERPNext employees with salary from contract
from_erpnext as (

    select
        {{ dbt_utils.generate_surrogate_key(['e.employee_id', "'maria_erp'"]) }} as employee_key,
        e.employee_id,
        e.employee_name,
        e.department,
        null                            as division,
        e.employment_type,
        c.base_salary,
        null::numeric                   as billing_rate,
        e.department                    as cost_center,
        'maria_erp'                     as _source
    from erpnext_employees e
    left join erpnext_contracts c
        on e.employee_id = c.employee_id

),

final as (

    select * from from_odoo
    union all
    select * from from_erpnext

)

select * from final
