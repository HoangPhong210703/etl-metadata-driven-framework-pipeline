{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    dim_organization — Company / Division / Department hierarchy
    Grain: one row per department (finest organizational level)
    Sources: savvycom_unit (divisions), hr_department (Odoo CRM departments),
             tabDepartment (ERPNext departments)
#}

with odoo_units as (

    select
        id::text                    as unit_id,
        name                        as division_name,
        department_id::text          as division_code,
        'Savvycom'                  as company_name
    from {{ ref('silver__accounting__savvycom_unit') }}

),

odoo_departments as (

    select
        id::text                    as department_id,
        name                        as department_name,
        complete_name               as department_full_name,
        company_id,
        parent_path
    from {{ ref('silver__accounting__hr_department') }}

),

erpnext_departments as (

    select
        name                        as department_code,
        department_name,
        company,
        parent_department,
        is_group
    from {{ ref('silver__project__tab_department') }}
    where coalesce(is_group, 0) = 0

),

-- Odoo departments joined to units for division context
odoo_combined as (

    select
        {{ dbt_utils.generate_surrogate_key(['d.department_id', "'postgres_crm'"]) }} as org_key,
        'Savvycom'                  as company_name,
        u.division_name,
        u.division_code,
        d.department_name,
        d.department_id             as department_code,
        'postgres_crm'              as _source
    from odoo_departments d
    left join odoo_units u
        on d.parent_path like '%/' || u.unit_id || '/%'

),

-- ERPNext departments
erpnext_combined as (

    select
        {{ dbt_utils.generate_surrogate_key(['e.department_code', "'maria_erp'"]) }} as org_key,
        coalesce(e.company, 'Savvycom')  as company_name,
        e.parent_department              as division_name,
        null                             as division_code,
        e.department_name,
        e.department_code,
        'maria_erp'                      as _source
    from erpnext_departments e

),

final as (

    select * from odoo_combined
    union all
    select * from erpnext_combined

)

select * from final
