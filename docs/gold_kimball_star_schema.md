# Gold Layer — Kimball Star Schema

## Overview

The gold layer implements a Kimball-style dimensional model for **Profit & Loss (PnL) reporting**. It consumes cleaned/deduplicated data from the silver layer and organizes it into conformed dimensions, fact tables, and pre-aggregated report models.

All gold models live in two schemas:
- `gold__common` — shared dimensions (dim_date)
- `gold__pnl` — all PnL dimensions, facts, and reports

## Star Schema Diagram

```
                          ┌──────────────────┐
                          │   dim_date       │
                          │──────────────────│
                          │ date_key (PK)    │
                          │ date_actual      │
                          │ year             │
                          │ month            │
                          │ is_working_day   │
                          │ is_holiday       │
                          │ working_day_of_  │
                          │   month          │
                          │ total_working_   │
                          │   days_in_month  │
                          └────────┬─────────┘
                                   │
┌──────────────────┐     ┌────────┴──────────┐     ┌──────────────────┐
│ dim_organization │     │ fct_revenue_      │     │  dim_project     │
│──────────────────│     │   monthly         │     │──────────────────│
│ org_key (PK)     │     │──────────────────-│     │ project_key (PK) │
│ company_name     │     │ revenue_monthly_  │     │ project_id       │
│                  │◄────│   key (PK)        │────►│ project_name     │
│                  │     │ date_key (FK)     │     │ project_type     │
│ department_name  │     │ project_key (FK)  │     │ market           │
│ department_code  │     │ org_key (FK)      │     │ project_status   │
│ _source          │     │ revenue_type      │     │ total_sales_     │
└──────────────────┘     │ contract_revenue  │     │   amount         │
                         │ revenue_forecast  │     │ plan_complete_   │
                         │ revenue_actual    │     │   rate           │
                         └───────────────────┘     │ actual_complete_ │
                                                   │   rate           │
┌──────────────────┐     ┌───────────────────┐     │ _source          │
│ dim_employee     │     │ fct_cost_monthly  │     └──────────────────┘
│──────────────────│     │───────────────────│
│ employee_key(PK) │     │ cost_monthly_     │     ┌──────────────────┐
│ employee_id      │◄────│   key (PK)        │────►│dim_cost_category │
│ employee_name    │     │ date_key (FK)     │     │──────────────────│
│ department       │     │ employee_key (FK) │     │ cost_category_   │
│ employment_type  │     │ project_key (FK)  │     │   key (PK)       │
│ base_salary      │     │ org_key (FK)      │     │ cost_category    │
│ billing_rate     │     │ cost_category_    │     │ cost_group       │
│ _source          │     │   key (FK)        │     │ description      │
└──────────────────┘     │ cost_actual       │     └──────────────────┘
         │               │ cost_forecast     │
         │               └───────────────────┘
         │
         │               ┌───────────────────┐
         │               │fct_headcount_     │
         └──────────────►│  monthly          │
                         │───────────────────│
                         │ headcount_monthly_│
                         │   key (PK)        │
                         │ date_key (FK)     │
                         │ employee_key (FK) │
                         │ org_key (FK)      │
                         │ is_active         │
                         │ is_billable       │
                         │ is_pool           │
                         │ is_training       │
                         │ headcount_value   │
                         │ total_salary      │
                         └───────────────────┘
```



## Dimensions

### dim_date (gold__common)
- **Grain:** one row per calendar day
- **Range:** 2020-01-01 to 2050-12-31
- **Schema:** `gold__common`
- **Source:** 
- **Key columns:**
- **Role:** conformed date dimension shared across all fact tables; provides working day calculations for cost proration and revenue forecasting

### dim_organization
- **Grain:** one row per department (finest organizational level)
- **Sources:**
- **Key columns:** 

### dim_project
- **Grain:** one row per project per source system
- **Sources:**
- **Key columns:** 

### dim_employee
- **Grain:** one row per employee per source system
- **Sources:**
- **Key columns:**

### dim_cost_category (seed)
- **Grain:** one row per cost classification
- **Materialized as:** dbt seed (`dbt/seeds/gold__pnl__dim_cost_category.csv`)
- **Groups:**
  - **Member Cost:** member_salary, member_bonus, member_overtime
  - **Project Expense:** project_expense
  - **Operational:** HR/Interviews, Training/Resource Pool, Presale

## Fact Tables

### fct_revenue_monthly
- **Grain:** one row per (month, project)
- **Materialized:** table
- **Current state:** Fix cost revenue only (teambase requires daily timesheet source)
- **Revenue types:**
  - **Fix Cost:** `contract_revenue × completion_rate` (currently absolute; requirements specify delta: `this_month_rate - last_month_rate`)
  - **Teambase:** placeholder — needs `project_contract_headcount.rate × actual_hours`
- **FKs:** `date_key` → dim_date, `project_key` → dim_project, `org_key` → dim_organization

### fct_cost_monthly
- **Grain:** one row per (month, employee, project, cost_category)
- **Materialized:** table
- **Current state:** placeholder — all data depends on daily timesheet source for working day proration
- **Cost types:**
  - **Member Salary:** `direct_cost × (actual_working_days / total_working_days)`
  - **Project Bonus:** `project_bonus × (working_days / total_working_days)`
  - **Overtime:** 
- **Missing sources:** 
- **FKs:** `date_key` → dim_date, `employee_key` → dim_employee, `project_key` → dim_project, `org_key` → dim_organization, `cost_category_key` → dim_cost_category

### fct_headcount_monthly
- **Grain:** one row per (month, employee)
- **Materialized:** table
- **Current state:** placeholder — depends on daily timesheet for activity detection
- **Flags:** `is_active`, `is_billable`, `is_hr_project`, `is_pool`, `is_training`
- **Derived KPIs:**
  - Billable Rate = billable_count / total_headcount
  - Busy Rate = (billable + HR project) / total_headcount (excludes presale/internal/training)
  - Available HC = count where is_pool
  - Dev Avg Salary = total_salary / active_count
- **FKs:** `date_key` → dim_date, `employee_key` → dim_employee, `org_key` → dim_organization

## Report Models

Report models sit on top of facts + dimensions. They pre-aggregate data for specific dashboard widgets.

### Main Dashboard

| Model | Feature | Grain | Sources |
|-------|---------|-------|---------|
| `rpt_monthly_pnl` | P&L (cost/revenue ratio), Total Revenue by Month, Total Cost by Month | month | fct_revenue_monthly + fct_cost_monthly |
| `rpt_rate_metrics` | Busy Rate, Billable Rate | month | fct_headcount_monthly |
| `rpt_revenue_mix` | Revenue Percentage | month × revenue_type | fct_revenue_monthly |
| `rpt_cost_mix` | Cost Percentage | month × cost_category | fct_cost_monthly + dim_cost_category |

### Human Resource

| Model | Feature | Grain | Sources |
|-------|---------|-------|---------|
| `rpt_hr_summary` | Dev Avg Salary, Total HC, Outsource HC, Internal HC, Training HC, Available HC | month × division | fct_headcount_monthly + dim_organization + dim_employee |

### Revenue Details Report

| Model | Feature | Grain | Sources |
|-------|---------|-------|---------|
| `rpt_revenue_by_project` | Revenue by project (split by department, project type, market) | month × project | fct_revenue_monthly + dim_project |
| `rpt_revenue_by_member` | Project revenue by member | month × employee × project | placeholder (needs tabProject User + project_contract_headcount) |

### Cost Report

| Model | Feature | Grain | Sources |
|-------|---------|-------|---------|
| `rpt_cost_summary` | Cost report summary, Total cost, Production / HR / Training / Presale / Resource Pool cost | month × division | fct_cost_monthly + dim_organization |

### Employee Performance

| Model | Feature | Grain | Sources |
|-------|---------|-------|---------|
| `rpt_employee_performance` | Employee performance summary, Employee performance details | month × employee × project | placeholder (needs tabProject User + employee_direct_cost) |

### KPI 

| Model | Feature | Grain | Sources |
|-------|---------|-------|---------|
| `rpt_kpi_finance` | Finance report (weekly/monthly revenue, cost, P&L summary) | week or month | rpt_monthly_pnl |
| `rpt_kpi_okr` | OKR tracking (target vs actual for key objectives) | month | TBD — needs OKR target source |
| `rpt_kpi_delivery` | Deliver Organization (project delivery status, on-time rate) | month × project | dim_project + fct_revenue_monthly |
| `rpt_kpi_recruitment` | Recruitment metrics (open positions, hired, time-to-fill) | month | TBD — needs recruitment/hiring source |
| `rpt_kpi_key_projects` | Key project status and health summary | month × project | dim_project + fct_revenue_monthly + fct_cost_monthly |
| `rpt_kpi_presale` | Presale project pipeline and conversion | month × project | TBD — needs presale pipeline source |
| `rpt_kpi_tracking` | KPI tracking (10 data types — consolidated KPI scorecard) | month × kpi_type | All fact + report models |

## Surrogate Key Strategy

All dimension surrogate keys use `dbt_utils.generate_surrogate_key()` (MD5 hash) over the natural key + `_source` discriminator:

- `dim_date.date_key` — integer YYYYMMDD (not MD5, for join efficiency)
- `dim_organization.org_key` — MD5(department_code, _source)
- `dim_project.project_key` — MD5(project_id, _source)
- `dim_employee.employee_key` — MD5(employee_id, _source)
- `dim_cost_category.cost_category_key` — natural text key from seed

Fact table surrogate keys are MD5 hashes of their composite FK columns.

## Multi-Source Pattern

Each dimension unions data from multiple source systems using a `_source` discriminator column:

| _source | System | Dimension PK |
|---------|--------|-------------|
| `postgres_timesheet` | Odoo Timesheet | `id` (integer) |
| `postgres_crm` | Odoo CRM | `id` (integer) |
| `maria_erp` | ERPNext | `name` (text) |

This means the same logical entity (e.g. an employee) can appear as two rows in a dimension — one per source system — each with its own surrogate key. Fact tables reference one specific `_source` per row.

## Naming Conventions

```
gold__{domain}__{model_type}_{name}

Domain:     common, pnl
Model type: dim (dimension), fct (fact), rpt (report)
```

Examples:
- `gold__common__dim_date`
- `gold__pnl__dim_project`
- `gold__pnl__fct_revenue_monthly`
- `gold__pnl__rpt_monthly_pnl`
