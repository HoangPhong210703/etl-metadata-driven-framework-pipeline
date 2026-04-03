{{ config(
    materialized='table',
    schema='gold__pnl'
) }}

{#
    rpt_cost_summary — Cost breakdown by category and division
    Powers: Cost Report (production, HR, training, presale, resource pool, total)
    Grain: one row per (month, division, cost_type)

    Cost types from requirements:
      - production_cost     → project expense (fix cost + teambase member cost)
      - hr_cost             → headcount_rate × interview hours
      - training_cost       → headcount_rate × training/RP hours
      - presale_cost        → headcount_rate × presale project hours
      - resource_pool_cost  → pool employee cost
      - total_cost          → sum of all above

    Placeholder metrics:
      All cost types require timesheet data for allocation.
      Currently fct_cost_monthly has salary/overtime placeholders.
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

dim_org as (

    select
        org_key,
        company_name,
        division_name,
        _source
    from {{ ref('gold__pnl__dim_organization') }}

),

-- From fct_cost_monthly (currently placeholder)
cost_by_org as (

    select
        c.date_key,
        c.org_key,
        sum(c.cost_actual) filter (where c.cost_category_key in ('member_salary', 'member_overtime'))
                                            as production_cost_actual,
        sum(c.cost_forecast) filter (where c.cost_category_key in ('member_salary', 'member_overtime'))
                                            as production_cost_forecast
    from {{ ref('gold__pnl__fct_cost_monthly') }} c
    group by c.date_key, c.org_key

),

final as (

    select
        d.month_date,
        d.year,
        d.month,
        o.company_name,
        o.division_name,

        coalesce(c.production_cost_actual, 0)   as production_cost_actual,
        coalesce(c.production_cost_forecast, 0) as production_cost_forecast,
        null::numeric                           as hr_cost_actual,           -- placeholder: needs interview hour tracking
        null::numeric                           as hr_cost_forecast,
        null::numeric                           as training_cost_actual,     -- placeholder: needs training hour tracking
        null::numeric                           as training_cost_forecast,
        null::numeric                           as presale_cost_actual,      -- placeholder: needs presale hour tracking
        null::numeric                           as presale_cost_forecast,
        null::numeric                           as resource_pool_cost_actual,-- placeholder: needs pool hour tracking
        null::numeric                           as resource_pool_cost_forecast,

        -- Total cost
        coalesce(c.production_cost_actual, 0)   as total_cost_actual,
        coalesce(c.production_cost_forecast, 0) as total_cost_forecast

    from dim_date d
    cross join dim_org o
    left join cost_by_org c
        on d.date_key = c.date_key
        and o.org_key = c.org_key

)

select * from final
