"""Impact metric calculation + persistence.

Turns agent outputs into explainable, quantifiable impact rows in
`impact_metrics`. Each row keeps baseline_value/optimized_value +
calculation metadata so the Tracks/Impact dashboard shows real,
defensible numbers instead of magic constants.

Only metrics with actual underlying data are written. If a metric
needs a baseline that does not exist, it is skipped — never fabricated.
"""

from app.core.config import get_settings

settings = get_settings()


async def record_impact_metrics(
    sb,
    farm_id: str,
    farmer_id: str,
    agent_run_id: str | None,
    results: list,
    context: dict | None = None,
) -> list[dict]:
    """Compute + persist impact metrics for one graph execution."""
    if not farmer_id:
        return []

    by_agent = {}
    for item in results or []:
        if item.get("status") == "success":
            by_agent[item["agent"]] = item.get("output")

    metrics = []

    water = _water_metric(by_agent.get("irrigation"))
    if water:
        metrics.append(water)

    food = _food_rescue_metric(by_agent.get("demand_matching"))
    if food:
        metrics.extend(food)

    yield_gain = _yield_gain_metric(sb, farm_id, by_agent.get("yield"))
    if yield_gain:
        metrics.append(yield_gain)

    if not metrics:
        return []

    rows = []
    for m in metrics:
        row = {
            "farmer_id": farmer_id,
            "farm_id": farm_id,
            "metric_type": m["metric_type"],
            "value": m["value"],
            "unit": m.get("unit"),
            "period": m.get("period"),
            "baseline_value": m.get("baseline_value"),
            "optimized_value": m.get("optimized_value"),
            "metadata": m.get("metadata") or {},
            "source": m.get("source", "smart_farming_agent"),
            "measured_or_estimated": m.get("measured_or_estimated", "estimated"),
            "agent_run_id": agent_run_id,
        }
        resp = sb.table("impact_metrics").insert(row).execute()
        if resp.data:
            rows.append(resp.data[0])
    return rows


def _water_metric(irrigation_output) -> dict | None:
    """Water saved from the irrigation decision.

    Baseline: watering for the default duration at pump flow.
    Optimized: the agent's recommended duration (or 0 when skipped).
    """
    if not irrigation_output:
        return None

    decision = irrigation_output.get("decision")
    duration = float(irrigation_output.get("recommended_duration_minutes") or 0)

    baseline_l = settings.DEFAULT_WATERING_MINUTES * settings.PUMP_FLOW_LITERS_PER_MIN
    recommended_l = duration * settings.PUMP_FLOW_LITERS_PER_MIN
    saved_l = max(baseline_l - recommended_l, 0.0)

    return {
        "metric_type": "water_saved_liters",
        "value": round(saved_l, 2),
        "unit": "L",
        "baseline_value": round(baseline_l, 2),
        "optimized_value": round(recommended_l, 2),
        "metadata": {
            "decision": decision,
            "recommended_duration_minutes": duration,
            "pump_flow_liters_per_min": settings.PUMP_FLOW_LITERS_PER_MIN,
            "default_watering_minutes": settings.DEFAULT_WATERING_MINUTES,
            "formula": "water_saved = (default_duration - recommended_duration) * pump_flow",
        },
        "source": "irrigation_agent",
        "measured_or_estimated": "estimated",
    }


def _food_rescue_metric(demand_output) -> list[dict]:
    """Food rescued + economic value + CO2e avoided from demand matching."""
    if not demand_output:
        return []

    rescued_kg = 0.0
    revenue_inr = 0.0
    for matches in demand_output:
        if not matches:
            continue
        for m in matches:
            qty = float(m.get("quantity_to_sell_kg") or m.get("quantity") or 0)
            price = float(m.get("offered_price") or 0)
            rescued_kg += qty
            revenue_inr += qty * price

    if rescued_kg <= 0:
        return []

    co2e = rescued_kg * settings.CO2E_FACTOR_KG_PER_KG_FOOD
    return [
        {
            "metric_type": "food_rescued_kg",
            "value": round(rescued_kg, 2),
            "unit": "kg",
            "baseline_value": 0.0,
            "optimized_value": round(rescued_kg, 2),
            "metadata": {
                "eligible_food_kg": round(rescued_kg, 2),
                "waste_avoided_kg": round(rescued_kg, 2),
                "formula": "rescued = sum of matched quantity_to_sell_kg",
            },
            "source": "demand_matching_agent",
        },
        {
            "metric_type": "economic_value_recovered_inr",
            "value": round(revenue_inr, 2),
            "unit": "INR",
            "baseline_value": 0.0,
            "optimized_value": round(revenue_inr, 2),
            "metadata": {
                "rescued_food_kg": round(rescued_kg, 2),
                "recovery_price_per_kg": round(revenue_inr / rescued_kg, 2) if rescued_kg else 0,
                "formula": "value = sum(quantity * offered_price)",
            },
            "source": "demand_matching_agent",
        },
        {
            "metric_type": "co2e_avoided_kg",
            "value": round(co2e, 2),
            "unit": "kg CO2e",
            "baseline_value": 0.0,
            "optimized_value": round(co2e, 2),
            "metadata": {
                "waste_avoided_kg": round(rescued_kg, 2),
                "emission_factor_kg_co2e_per_kg": settings.CO2E_FACTOR_KG_PER_KG_FOOD,
                "formula": "co2e = waste_avoided * emission_factor",
            },
            "source": "demand_matching_agent",
        },
    ]


def _yield_gain_metric(sb, farm_id: str, yield_output) -> dict | None:
    """Yield gain % vs the farm's own historical baseline, when it exists."""
    if not yield_output:
        return None

    expected = float(yield_output.get("expected_yield_kg") or 0)
    if expected <= 0:
        return None

    baseline_resp = sb.table("crop_performance_history") \
        .select("yield_kg").eq("farm_id", farm_id).limit(1).execute()
    baseline_rows = baseline_resp.data or []
    if not baseline_rows:
        return None

    baseline_yield = float(baseline_rows[0].get("yield_kg") or 0)
    if baseline_yield <= 0:
        return None

    gain_pct = (expected - baseline_yield) / baseline_yield * 100.0
    return {
        "metric_type": "yield_gain_pct",
        "value": round(gain_pct, 2),
        "unit": "%",
        "baseline_value": round(baseline_yield, 2),
        "optimized_value": round(expected, 2),
        "metadata": {
            "baseline_yield_kg": round(baseline_yield, 2),
            "expected_yield_kg": round(expected, 2),
            "formula": "gain = (expected - baseline) / baseline * 100",
        },
        "source": "yield_agent",
        "measured_or_estimated": "estimated",
    }
