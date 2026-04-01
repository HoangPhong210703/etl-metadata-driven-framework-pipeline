{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    dim_project — Project details for PnL reporting
    Grain: one row per project
    Sources: savvycom_project_project (Odoo timesheet), project_project (Odoo CRM),
             tabProject + tabProject Package (ERPNext)
#}

with odoo_ts_projects as (

    select
        id::text                        as project_id,
        name                            as project_name,
        project_type,
        unit_name                       as market,
        status                          as project_status,
        unit_id,
        'postgres_timesheet'            as _source
    from {{ ref('silver__accounting__savvycom_project_project') }}

),

erpnext_projects as (

    select
        name                            as project_id,
        project_name,
        null                            as project_type,
        status                          as project_status,
        total_sales_amount,
        company,
        department,
        expected_start_date,
        expected_end_date,
        'maria_erp'                     as _source
    from {{ ref('silver__project__tab_project') }}

),

-- Aggregate completion rates from tabProject Package per project
erpnext_packages as (

    select
        parent                          as project_id,
        avg(plan_complete_rate)         as plan_complete_rate,
        avg(actual_complete_rate)       as actual_complete_rate
    from {{ ref('silver__project__tab_project_package') }}
    where parent is not null
    group by parent

),

-- Primary source: Odoo timesheet projects (richest PnL data)
from_odoo_ts as (

    select
        {{ dbt_utils.generate_surrogate_key(['p.project_id', 'p._source']) }} as project_key,
        p.project_id,
        p.project_name,
        p.project_type,
        p.market,
        p.project_status,
        null::numeric                   as total_sales_amount,
        null::numeric                   as gross_margin,
        null::numeric                   as plan_complete_rate,
        null::numeric                   as actual_complete_rate,
        p._source
    from odoo_ts_projects p

),

-- ERPNext projects with package completion rates
from_erpnext as (

    select
        {{ dbt_utils.generate_surrogate_key(['p.project_id', 'p._source']) }} as project_key,
        p.project_id,
        p.project_name,
        p.project_type,
        null                            as market,
        p.project_status,
        p.total_sales_amount,
        null::numeric                   as gross_margin,
        pkg.plan_complete_rate,
        pkg.actual_complete_rate,
        p._source
    from erpnext_projects p
    left join erpnext_packages pkg
        on p.project_id = pkg.project_id

),

final as (

    select * from from_odoo_ts
    union all
    select * from from_erpnext

)

select * from final
