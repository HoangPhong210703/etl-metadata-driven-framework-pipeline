"""Execution DAG (sil2gold) — builds gold-layer dimensional models from silver.
Task chain: run_dbt_seed → run_dbt_gold → test_dbt_gold."""

import sys
from datetime import datetime

from airflow import DAG  # type: ignore
from airflow.operators.python import PythonOperator  # type: ignore

sys.path.insert(0, "/opt/airflow")
from src.pipeline.audit import audited
from src.pipeline.alert import dag_failure_callback, dag_success_callback


def _setup_dbt_env():
    """Load warehouse credentials and set dbt env vars."""
    from src.pipeline.credentials import load_warehouse_credentials
    from src.pipeline.dbt_runner import set_dbt_env_vars
    set_dbt_env_vars(load_warehouse_credentials())


@audited
def run_dbt_seed(**kwargs):
    """Load dbt seeds (e.g. dim_cost_category)."""
    from src.pipeline.dbt_runner import run_dbt_seed
    from src.pipeline.settings import DBT_PROJECT_DIR
    _setup_dbt_env()
    run_dbt_seed(DBT_PROJECT_DIR)
    print("[sil2gold] dbt seed complete")


@audited
def run_dbt_gold(**kwargs):
    """Run dbt gold models (dimensional star schema)."""
    from src.pipeline.dbt_runner import run_dbt
    from src.pipeline.settings import DBT_PROJECT_DIR
    _setup_dbt_env()
    run_dbt(DBT_PROJECT_DIR, selectors=["gold"])
    print("[sil2gold] dbt gold models complete")


@audited
def test_dbt_gold(**kwargs):
    """Run dbt tests for gold models."""
    from src.pipeline.dbt_runner import run_dbt_test, parse_dbt_results
    from src.pipeline.settings import DBT_PROJECT_DIR

    _setup_dbt_env()
    run_dbt_test(DBT_PROJECT_DIR, selectors=["gold"])

    results = parse_dbt_results(DBT_PROJECT_DIR)
    passed = [r for r in results if r["status"] == "pass"]
    failed = [r for r in results if r["status"] in ("fail", "error")]
    warned = [r for r in results if r["status"] == "warn"]

    print(f"[sil2gold] dbt tests: {len(passed)} passed, {len(failed)} failed, {len(warned)} warnings")

    return {
        "test_count": len(results),
        "passed": len(passed),
        "failed": len(failed),
        "warnings": len(warned),
    }


with DAG(
    dag_id="sil2gold__build_mart",
    description="Build gold-layer PnL star schema from silver (seed → gold → test)",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    on_success_callback=dag_success_callback,
    on_failure_callback=dag_failure_callback,
    catchup=False,
    tags=["execution", "sil2gold", "dbt", "gold"],
) as dag:
    seed = PythonOperator(task_id="run_dbt_seed", python_callable=run_dbt_seed)
    gold = PythonOperator(task_id="run_dbt_gold", python_callable=run_dbt_gold)
    test = PythonOperator(task_id="test_dbt_gold", python_callable=test_dbt_gold)

    seed >> gold >> test
