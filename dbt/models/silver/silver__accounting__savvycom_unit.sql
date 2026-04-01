{{ config(
    materialized='incremental',
    unique_key=['id', '_source'],
    schema='sil__accounting',
    on_schema_change='append_new_columns'
) }}

{{ silver_dedup(['stg__accounting__postgres_timesheet'], 'savvycom_unit') }}
