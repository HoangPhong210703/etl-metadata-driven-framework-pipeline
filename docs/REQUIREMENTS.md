# Consolidated Requirements — PnL Dashboard ETL Pipeline

## 1. Project Objective

Build a metadata-driven ETL pipeline producing a **Kimball star schema** for **Profit & Loss (PnL) reporting** dashboards. Visualized via **Metabase** connected to a PostgreSQL warehouse.

---

## 2. Source Systems

| Source | Type | Host | Schema | Data Subject |
|--------|------|------|--------|-------------|
| `postgres_crm` | PostgreSQL (Odoo CRM) | 10.22.4.47:15432 | public | accounting |
| `postgres_timesheet` | PostgreSQL (Odoo Timesheet) | 10.22.4.47:5432 | public | accounting |
| `maria_erp` | MariaDB (ERPNext) | 10.22.5.26:3306 | appdb | project |

### Ingested Tables (64 total)

- **postgres_crm** (18 tables): `account_*`, `project_project`, `crm_lead`, `hr_department`
- **postgres_timesheet** (29 tables): `account_*`, `savvycom_project_project`, `savvycom_project_project_member`, `adjusted_attendance_register`, `hr_employee`, `savvycom_unit`, `sale_order`, `cost_allocation_unit`
- **maria_erp** (4 + 3 = 7 tables): `tabProject`, `tabProject Model`, `tabProject Package`, `tabProject User`, `tabEmployee`, `tabEmployment Contract`, `tabDepartment`, `tabHoliday`

---

## 3. Pipeline Architecture

```
Source RDBMS → Bronze (Parquet) → Staging (PostgreSQL) → Silver (dbt dedup) → Gold (dbt star schema) → Metabase
```

| Layer | Technology | Trigger |
|-------|-----------|---------|
| src2brz | dlt → Parquet files | Button DAG (manual) |
| brz2stg | dlt → PostgreSQL warehouse | Auto-triggered from src2brz |
| stg2sil | dbt (snapshot + silver models) | Airflow Dataset event from brz2stg |
| sil2gold | dbt (seed → gold → test) | Manual / scheduled |

### Orchestration
- Apache Airflow 2.10.4, LocalExecutor, parallelism: 4
- All config CSV-driven (`config/`), no hardcoded table lists
- Docker Compose deployment (dev + production override with Metabase)

---

## 4. Gold Layer — Star Schema Design

### 4.1 Dimensions

| Dimension | Schema | Grain | Sources | Status |
|-----------|--------|-------|---------|--------|
| `dim_date` | gold__common | 1 row per calendar day (2020–2050) | Generated + `tabHoliday` | **Built** |
| `dim_organization` | gold__pnl | 1 row per department | `savvycom_unit`, `hr_department`, `tabDepartment` | **Built** |
| `dim_project` | gold__pnl | 1 row per project per source | `savvycom_project_project`, `tabProject`, `tabProject Package` | **Built** |
| `dim_employee` | gold__pnl | 1 row per employee per source | `hr_employee`, `tabEmployee`, `tabEmployment Contract` | **Built** |
| `dim_cost_category` | gold__pnl | 1 row per cost classification | dbt seed CSV | **Built** |

### 4.2 Fact Tables

| Fact Table | Grain | Status | Blockers |
|-----------|-------|--------|----------|
| `fct_revenue_monthly` | month x project | **Partial** — fix cost only (absolute rate, not delta) | Missing: `projects_contract`, `fixcost_delivery_plan`, `project_contract_headcount`; Teambase needs daily timesheet |
| `fct_cost_monthly` | month x employee x project x cost_category | **Placeholder** — empty result set | Missing: daily timesheet for working day proration; `employee_direct_cost` |
| `fct_headcount_monthly` | month x employee | **Placeholder** — empty result set | Missing: daily timesheet for activity detection |

### 4.3 Report Models

| Report Model | Dashboard Widget | Status | Blockers |
|-------------|-----------------|--------|----------|
| `rpt_monthly_pnl` | P&L ratio, Total Revenue/Cost by Month | **Placeholder** | Depends on fct_revenue + fct_cost |
| `rpt_rate_metrics` | Busy Rate, Billable Rate | **Placeholder** | Depends on fct_headcount |
| `rpt_revenue_mix` | Revenue Percentage pie chart | **Placeholder** | Depends on fct_revenue |
| `rpt_cost_mix` | Cost Percentage pie chart | **Placeholder** | Depends on fct_cost |
| `rpt_hr_summary` | Dev Avg Salary, HC breakdown | **Placeholder** | Depends on fct_headcount + dim_employee |
| `rpt_revenue_by_project` | Revenue by project (dept/market/type) | **Placeholder** | Depends on fct_revenue + project→division mapping |
| `rpt_revenue_by_member` | Project revenue by member | **Placeholder** | Needs `tabProject User`, `project_contract_headcount` |
| `rpt_cost_summary` | Cost breakdown by type/division | **Placeholder** | Depends on fct_cost |
| `rpt_employee_performance` | Employee revenue/cost/profit | **Placeholder** | Needs `tabProject User`, `employee_direct_cost`, timesheet |

### 4.4 KPI Models (Not Yet Created)

| Report Model | Description | Blockers |
|-------------|-------------|----------|
| `rpt_kpi_finance` | Weekly/monthly revenue, cost, P&L summary | Depends on rpt_monthly_pnl |
| `rpt_kpi_okr` | OKR tracking (target vs actual) | Needs OKR target source (TBD) |
| `rpt_kpi_delivery` | Project delivery status, on-time rate | Depends on dim_project + fct_revenue |
| `rpt_kpi_recruitment` | Open positions, hired, time-to-fill | Needs recruitment/hiring source (TBD) |
| `rpt_kpi_key_projects` | Key project health summary | Depends on dim_project + fct_revenue + fct_cost |
| `rpt_kpi_presale` | Presale pipeline and conversion | Needs presale pipeline source (TBD) |
| `rpt_kpi_tracking` | Consolidated KPI scorecard (10 types) | Depends on all fact + report models |

---

## 5. Missing Source Tables (Critical Blockers)

These tables exist in ERPNext / source systems but are **not yet ingested** into the pipeline. They block most gold-layer calculations.

| Missing Table | Source System | Needed For | Key Columns |
|--------------|--------------|-----------|-------------|
| `projects_contract` | maria_erp | Fix cost contract revenue | `contract_revenue` |
| `fixcost_delivery_plan` | maria_erp | Monthly completion rates (plan vs actual) | `complete_rate`, `actual_complete_rate` |
| `project_contract_headcount` | maria_erp | Teambase hourly billing rates | `rate` ($/hour per employee per project) |
| `employee_direct_cost` | maria_erp | Cost calculations (replaces base_salary) | `direct_cost`, `project_bonus` |
| `fixcost_project_package` | maria_erp | Package-level project costs | (cost data per project) |

### Already Ingested But Not Fully Utilized

| Table | Source | Current Use | Additional Data Available |
|-------|--------|------------|--------------------------|
| `tabProject User` | maria_erp | Ingested but not in silver/gold | `employee_code`, `effort_rate`, `performance_rate` |
| `adjusted_attendance_register` | postgres_timesheet | Ingested but not in silver/gold | `overtime_hours` (column name TBD) |
| `savvycom_project_project_member` | postgres_timesheet | In silver sources but not used in gold | Project member assignments |

---

## 6. Metric Requirements

### 6.1 Revenue Metrics

| Metric | Formula | Required Sources |
|--------|---------|-----------------|
| Fix Cost Revenue (Forecast) | `contract_revenue x (this_month_plan_rate - last_month_plan_rate)` | `projects_contract`, `fixcost_delivery_plan` |
| Fix Cost Revenue (Actual) | `contract_revenue x (this_month_actual_rate - last_month_actual_rate)` | `projects_contract`, `fixcost_delivery_plan` |
| Teambase Revenue (Forecast) | `employee_rate x 8 x plan_working_days` | `project_contract_headcount`, dim_date |
| Teambase Revenue (Actual) | `employee_rate x actual_hours` | `project_contract_headcount`, timesheet |
| Fix Cost Member Revenue | `(effort / total_effort) x performance_rate x monthly_project_revenue` | `tabProject User` |
| Revenue Target/Budget | From CRM | Source TBD |

**Note:** Current implementation uses **absolute** completion rates (`contract x rate`). Requirements specify **delta-based** rates (`this_month - last_month`).

### 6.2 Cost Metrics

| Metric | Formula | Required Sources |
|--------|---------|-----------------|
| Member Cost (Forecast) | `direct_cost x (plan_working_day / total_working_day) + project_bonus x (plan_working_day / total_working_day)` | `employee_direct_cost`, dim_date |
| Member Cost (Actual) | `direct_cost x (actual_working_day / total_working_day) + project_bonus + salary x (OT_hour / 8 / total_working_day)` | `employee_direct_cost`, timesheet, `adjusted_attendance_register` |
| Fix Cost Project Cost | `SUM(member_cost) + (project_package x working_day / total_working_day)` | fct_cost + `fixcost_project_package` |
| Production Cost | `SUM(fixcost_project_cost) + SUM(teambase_project_cost)` | Calculated |
| HR Cost | `SUM(headcount_rate x total_interview_hours)` | Interview hour tracking (TBD) |
| Training Cost | `SUM(headcount_rate x training_or_RP_hours)` | Training hour tracking (TBD) |
| Presale Cost | `SUM(headcount_rate x presale_project_hours)` | Presale hour tracking (TBD) |
| Cost Target/Budget | Source TBD | Source TBD |

### 6.3 Headcount / HR Metrics

| Metric | Formula | Required Sources |
|--------|---------|-----------------|
| Billable Rate | `(headcount_in_billable_projects / total_headcount) x 100%` | Project assignments |
| Busy Rate | `(billable + HR_projects / total_headcount) x 100%` (excludes presale/internal/training) | Project assignments + type classification |
| Available HC | `COUNT(headcount in POOL projects)` | Pool project assignment |
| Dev Avg Salary | `total_salary / total_headcount` | Salary + active headcount |
| Turnover Rate | `(departed_count / avg_headcount) x 100%` | Employee departure data (TBD) |
| Outsource HC / Internal HC | By employment_type or contract_type | Classification data |
| Training HC | Headcount in training-type projects | Project type classification |

### 6.4 P&L Metrics

| Metric | Formula |
|--------|---------|
| P&L Forecast | `(cost_forecast / revenue_forecast) x 100%` |
| P&L Actual | `(cost_actual / revenue_actual) x 100%` |
| Gross Profit | `total_revenue - total_cost` |
| Gross Margin % | `gross_profit / total_revenue` |

---

## 7. Dashboard Sections (Metabase)

| Section | Widgets | Source Models |
|---------|---------|-------------|
| **Main Dashboard** | P&L ratio, Total Revenue by Month, Total Cost by Month, Busy Rate, Billable Rate, Revenue %, Cost % | rpt_monthly_pnl, rpt_rate_metrics, rpt_revenue_mix, rpt_cost_mix |
| **Human Resource** | Dev Avg Salary, Total/Outsource/Internal/Training/Available HC, Turnover Rate | rpt_hr_summary |
| **Revenue Details** | Revenue by project (by dept/market/type), Revenue by member | rpt_revenue_by_project, rpt_revenue_by_member |
| **Cost Report** | Total cost, Production/HR/Training/Presale/Resource Pool cost | rpt_cost_summary |
| **Employee Performance** | Revenue/cost/profit per employee per project | rpt_employee_performance |
| **KPI** | Finance, OKR, Delivery, Recruitment, Key Projects, Presale, Tracking | rpt_kpi_* (7 models, not yet created) |

---

## 8. Deployment Requirements

- **Target:** Linux VM (Ubuntu 22.04+), 4 CPU, 8 GB RAM, 50 GB disk
- **Stack:** Docker Compose (Airflow + dbt + dlt + Metabase)
- **Network:** Access to source databases (10.22.4.47 PostgreSQL, 10.22.5.26 MariaDB) and warehouse (10.22.4.47:5432/raw_db)
- **Ports:** 8080 (Airflow), 3000 (Metabase)
- **Secrets:** `.dlt/secrets.toml` (source DB creds), `.env` (Airflow, SMTP, warehouse, Metabase)
- **Status:** Deployment plan exists (`docs/superpowers/plans/2026-04-08-vm-deployment.md`), `deploy/README.md` created, scripts pending

---

## 9. Unresolved Dependencies

| Category | Item | Resolution Needed |
|----------|------|------------------|
| **Source data** | 5 missing ERPNext tables | Verify table names exist in ERPNext, add to `table_config.csv`, create silver models |
| **Source data** | `tabProject User` in staging but not in gold | Create silver model, wire into fct_revenue_monthly + rpt_revenue_by_member |
| **Source data** | `adjusted_attendance_register` overtime column | Confirm column name, create silver model, wire into fct_cost_monthly |
| **Mapping** | Project → Division mapping | Determine if `savvycom_project_project.unit_id → savvycom_unit` or `tabProject.department` |
| **Mapping** | Employee Odoo ↔ ERPNext cross-reference | No shared natural key; may need `tabProject User.employee_code` |
| **Business rule** | Revenue calculation: absolute vs delta rates | Current: absolute; required: delta (month-over-month) |
| **Business rule** | Cost: `direct_cost` vs `base_salary` | Requirements say `direct_cost` from `employee_direct_cost`; current uses `base_salary` from employment contract |
| **External source** | Revenue/cost targets/budgets | Source TBD (mentioned as "from CRM") |
| **External source** | OKR targets, recruitment metrics, presale pipeline | Sources completely TBD |
| **External source** | Interview/training/presale hour tracking | No identified source table |

---

## 10. Current State Summary

| Component | Status |
|-----------|--------|
| Pipeline infrastructure (Airflow + dlt + dbt) | **Complete** |
| Bronze + Staging layers (64 tables) | **Complete** |
| Silver layer (dedup + snapshots) | **Complete** |
| Gold dimensions (5) | **Built** |
| Gold fact tables (3) | **1 partial, 2 placeholder (empty)** |
| Gold report models (9) | **All placeholder** |
| Gold KPI models (7) | **Not created** |
| sil2gold DAG | **Built** |
| VM deployment | **Plan written, partially implemented** |
| Metabase dashboards | **Not started** |
