{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_hr_summary — Monthly Human Resource KPIs by division and company
    Powers: Human Resource dashboard widget
    Grain: one row per (month, division)

    Placeholder metrics:
      - dev_avg_salary          → total salary / active headcount
      - total_hc                → all active employees
      - outsource_hc            → external/outsource employees
      - internal_hc             → internal employees
      - training_hc             → employees in training projects
      - available_hc            → employees in pool projects
      - turnover_rate           → (departed / avg headcount) × 100
#}

with months as (

    select distinct
        (year * 10000 + month * 100 + 1)    as date_key,
        make_date(year, month, 1)           as month_date,
        year,
        month
    from {{ ref('gold__common__dim_date') }}
    where is_working_day = true
      and make_date(year, month, 1) <= current_date

),

dim_org as (

    select
        org_key,
        company_name,
        division_name,
        department_name,
        _source
    from {{ ref('gold__pnl__dim_organization') }}

),

headcount as (

    select
        date_key,
        org_key,
        count(*)                                                    as total_hc,
        sum(headcount_value)                                        as total_hc_value,
        count(*) filter (where is_pool = true)                      as available_hc,
        count(*) filter (where is_training = true)                  as training_hc,
        avg(total_salary)                                           as dev_avg_salary,
        sum(total_salary)                                           as total_salary
    from {{ ref('gold__pnl__fct_headcount_monthly') }}
    where is_active = true
    group by date_key, org_key

),

final as (

    select
        m.date_key,
        m.month_date,
        m.year,
        m.month,
        o.company_name,
        o.division_name,

        coalesce(h.total_hc, 0)             as total_hc,
        coalesce(h.total_hc_value, 0)       as total_hc_value,
        null::int                           as outsource_hc,        -- placeholder: needs employment_type classification
        null::int                           as internal_hc,         -- placeholder: needs employment_type classification
        coalesce(h.training_hc, 0)          as training_hc,
        coalesce(h.available_hc, 0)         as available_hc,
        null::numeric                       as turnover_rate,       -- placeholder: needs departure data
        h.dev_avg_salary,
        coalesce(h.total_salary, 0)         as total_salary

    from months m
    cross join dim_org o
    left join headcount h
        on m.date_key = h.date_key
        and o.org_key = h.org_key

)

select * from final
