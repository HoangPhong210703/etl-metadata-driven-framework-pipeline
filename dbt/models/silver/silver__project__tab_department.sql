{{ config(
    materialized='incremental',
    unique_key=['name', '_source'],
    schema='sil__project',
    on_schema_change='append_new_columns'
) }}

{{ silver_dedup(['stg__project__maria_erp'], 'tabDepartment', unique_key='name') }}
