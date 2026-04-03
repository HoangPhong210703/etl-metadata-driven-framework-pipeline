"""Create PnL dashboard cards in Metabase via API."""
import json
import urllib.request
import urllib.error

BASE = "http://localhost:3000/api"
DB_ID = 2
COLLECTION_ID = 5
DASHBOARD_ID = 2


def api(method, path, data=None, session=None):
    headers = {"Content-Type": "application/json"}
    if session:
        headers["X-Metabase-Session"] = session
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(f"{BASE}{path}", data=body, headers=headers, method=method)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def login():
    r = api("POST", "/session", {"username": "admin@savvycom.local", "password": "Savvycom@2024"})
    return r["id"]


def create_card(session, name, sql, display="table"):
    return api("POST", "/card", {
        "name": name,
        "collection_id": COLLECTION_ID,
        "dataset_query": {
            "type": "native",
            "native": {"query": sql},
            "database": DB_ID,
        },
        "display": display,
        "visualization_settings": {},
    }, session)["id"]


def main():
    s = login()
    print(f"Logged in")

    cards = []

    # 1. Revenue KPI
    cid = create_card(s, "Revenue KPI",
        "SELECT total_revenue_actual AS \"Total Revenue\", "
        "total_revenue_forecast AS \"Forecast\", "
        "gross_margin_pct AS \"Margin\" "
        "FROM gold__pnl.gold__pnl__rpt_monthly_pnl "
        "WHERE month_date = (SELECT MAX(month_date) FROM gold__pnl.gold__pnl__rpt_monthly_pnl "
        "WHERE total_revenue_actual > 0)",
        "scalar")
    cards.append(("Revenue KPI", cid))
    print(f"  Revenue KPI: {cid}")

    # 2. P&L KPI
    cid = create_card(s, "P&L KPI",
        "SELECT gross_profit_actual AS \"Gross Profit\", "
        "total_revenue_actual AS \"Revenue\", "
        "total_cost_actual AS \"Cost\" "
        "FROM gold__pnl.gold__pnl__rpt_monthly_pnl "
        "WHERE month_date = (SELECT MAX(month_date) FROM gold__pnl.gold__pnl__rpt_monthly_pnl "
        "WHERE total_revenue_actual > 0)",
        "scalar")
    cards.append(("P&L KPI", cid))
    print(f"  P&L KPI: {cid}")

    # 3. Busy Rate
    cid = create_card(s, "Busy Rate",
        "SELECT ROUND(COALESCE(busy_rate, 0) * 100, 1) AS \"Busy Rate %\", "
        "busy_count AS \"Busy\", total_headcount AS \"Total HC\" "
        "FROM gold__pnl.gold__pnl__rpt_rate_metrics "
        "WHERE month_date = (SELECT MAX(month_date) FROM gold__pnl.gold__pnl__rpt_rate_metrics "
        "WHERE total_headcount > 0)",
        "scalar")
    cards.append(("Busy Rate", cid))
    print(f"  Busy Rate: {cid}")

    # 4. Billable Rate
    cid = create_card(s, "Billable Rate",
        "SELECT ROUND(COALESCE(billable_rate, 0) * 100, 1) AS \"Billable Rate %\", "
        "billable_count AS \"Billable\", total_headcount AS \"Total HC\" "
        "FROM gold__pnl.gold__pnl__rpt_rate_metrics "
        "WHERE month_date = (SELECT MAX(month_date) FROM gold__pnl.gold__pnl__rpt_rate_metrics "
        "WHERE total_headcount > 0)",
        "scalar")
    cards.append(("Billable Rate", cid))
    print(f"  Billable Rate: {cid}")

    # 5. Total Revenue by Month
    cid = create_card(s, "Total Revenue by Month",
        "SELECT month_date AS \"Month\", "
        "total_revenue_actual AS \"Actual\", "
        "total_revenue_forecast AS \"Forecast\" "
        "FROM gold__pnl.gold__pnl__rpt_monthly_pnl "
        "ORDER BY month_date",
        "line")
    cards.append(("Revenue by Month", cid))
    print(f"  Revenue by Month: {cid}")

    # 6. P&L by Month
    cid = create_card(s, "P&L by Month",
        "SELECT month_date AS \"Month\", "
        "total_revenue_actual AS \"Revenue\", "
        "total_cost_actual AS \"Cost\", "
        "gross_profit_actual AS \"Profit\" "
        "FROM gold__pnl.gold__pnl__rpt_monthly_pnl "
        "ORDER BY month_date",
        "line")
    cards.append(("P&L by Month", cid))
    print(f"  P&L by Month: {cid}")

    # 7. Revenue Percentage
    cid = create_card(s, "Revenue Percentage",
        "SELECT revenue_type AS \"Revenue Type\", "
        "SUM(revenue_actual) AS \"Revenue\" "
        "FROM gold__pnl.gold__pnl__rpt_revenue_mix "
        "GROUP BY revenue_type "
        "ORDER BY SUM(revenue_actual) DESC",
        "pie")
    cards.append(("Revenue %", cid))
    print(f"  Revenue %: {cid}")

    # 8. Cost Percentage
    cid = create_card(s, "Cost Percentage",
        "SELECT COALESCE(cost_category, cost_category_key) AS \"Cost Category\", "
        "SUM(cost_actual) AS \"Cost\" "
        "FROM gold__pnl.gold__pnl__rpt_cost_mix "
        "GROUP BY COALESCE(cost_category, cost_category_key) "
        "ORDER BY SUM(cost_actual) DESC",
        "pie")
    cards.append(("Cost %", cid))
    print(f"  Cost %: {cid}")

    # Get existing dashboard cards
    dash = api("GET", f"/dashboard/{DASHBOARD_ID}", session=s)
    existing = []
    for dc in dash["dashcards"]:
        existing.append({
            "id": dc["id"],
            "card_id": dc["card_id"],
            "row": dc["row"] + 16,  # shift down to make room
            "col": dc["col"],
            "size_x": dc["size_x"],
            "size_y": dc["size_y"],
        })

    # Layout: 4 KPIs in a row, then 2 line charts, then 2 pies
    new_cards = [
        {"id": -20, "card_id": cards[0][1], "row": 0, "col": 0, "size_x": 4, "size_y": 3},   # Revenue KPI
        {"id": -21, "card_id": cards[1][1], "row": 0, "col": 4, "size_x": 4, "size_y": 3},   # P&L KPI
        {"id": -22, "card_id": cards[2][1], "row": 0, "col": 8, "size_x": 5, "size_y": 3},   # Busy Rate
        {"id": -23, "card_id": cards[3][1], "row": 0, "col": 13, "size_x": 5, "size_y": 3},  # Billable Rate
        {"id": -24, "card_id": cards[4][1], "row": 3, "col": 0, "size_x": 9, "size_y": 6},   # Revenue by Month
        {"id": -25, "card_id": cards[5][1], "row": 3, "col": 9, "size_x": 9, "size_y": 6},   # P&L by Month
        {"id": -26, "card_id": cards[6][1], "row": 9, "col": 0, "size_x": 9, "size_y": 7},   # Revenue %
        {"id": -27, "card_id": cards[7][1], "row": 9, "col": 9, "size_x": 9, "size_y": 7},   # Cost %
    ]

    all_cards = new_cards + existing
    api("PUT", f"/dashboard/{DASHBOARD_ID}", {"dashcards": all_cards}, s)
    print(f"\nDashboard updated with {len(all_cards)} total cards")
    print(f"View at: http://localhost:3000/dashboard/{DASHBOARD_ID}")


if __name__ == "__main__":
    main()
