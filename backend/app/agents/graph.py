"""LangGraph orchestration of the AgriTech agents.

Collects farm context, fans out to the specialized agents (irrigation, crop
health, yield, inventory, demand matching, next season) in parallel, then the
smart-farming supervisor aggregates their ACTUAL outputs into alerts + next
actions, and finally the impact layer turns those outputs into quantifiable
metrics.

A single `agent_run_id` (generated once per run) is threaded through every
node so all agent_results / irrigation_decisions / smart_farming_reviews /
mqtt_commands / impact_metrics from one execution are correlatable.

Every node catches its own exceptions and records them in `errors`, and each
result carries a `status` (success | failed | skipped | unavailable) so the
supervisor never mistakes a missing/failed agent for a healthy one.
"""

import operator
import uuid
from typing import Annotated, TypedDict

from langgraph.graph import StateGraph, START, END


class FarmAgentState(TypedDict):
    sb: object
    farm_id: str
    farmer_id: str | None
    agent_run_id: str
    image_ctx: dict | None
    inventory_params: list
    demand_requests: list
    context: dict
    results: Annotated[list, operator.add]
    errors: Annotated[list, operator.add]


async def collect_context(state: FarmAgentState) -> dict:
    sb = state["sb"]
    farm_id = state["farm_id"]
    context: dict = {}

    farm_resp = sb.table("farms").select("*").eq("id", farm_id).limit(1).execute()
    if farm_resp.data:
        farm = farm_resp.data[0]
        context["farm"] = farm
        context["farmer_id"] = state.get("farmer_id") or farm.get("farmer_id")

    field_resp = sb.table("field_area").select("*").eq("farm_id", farm_id).limit(1).execute()
    field = field_resp.data[0] if field_resp.data else None
    context["field"] = field

    dev_resp = sb.table("farm_devices").select("*").eq("farm_id", farm_id).limit(1).execute()
    context["device"] = dev_resp.data[0] if dev_resp.data else None

    return {"context": context}


async def irrigation_node(state: FarmAgentState) -> dict:
    from app.services.irrigation_agent_service import run_irrigation_decision
    try:
        out = await run_irrigation_decision(
            state["sb"], state["farm_id"], state.get("farmer_id"),
            agent_run_id=state.get("agent_run_id"),
        )
    except Exception as exc:
        return {"errors": [f"irrigation: {exc}"],
                "results": [{"agent": "irrigation", "output": None, "status": "failed"}]}
    return {"results": [{"agent": "irrigation", "output": out, "status": "success" if out else "unavailable"}]}


async def crop_health_node(state: FarmAgentState) -> dict:
    image = state.get("image_ctx")
    if not image:
        return {"results": [{"agent": "crop_health", "output": None, "status": "skipped"}]}
    from app.services.crop_health_service import run_crop_health
    try:
        out = await run_crop_health(
            state["sb"], image["image_id"], state["farm_id"], image["image_url"],
            image.get("crop_hint"), agent_run_id=state.get("agent_run_id"),
        )
    except Exception as exc:
        return {"errors": [f"crop_health: {exc}"],
                "results": [{"agent": "crop_health", "output": None, "status": "failed"}]}
    return {"results": [{"agent": "crop_health", "output": out, "status": "success"}]}


async def yield_node(state: FarmAgentState) -> dict:
    image = state.get("image_ctx")
    if not image:
        return {"results": [{"agent": "yield", "output": None, "status": "skipped"}]}
    from app.services.crop_health_service import run_yield_analysis
    try:
        out = await run_yield_analysis(
            state["sb"], image["image_id"], state["farm_id"], image["image_url"],
            image.get("crop_hint"), agent_run_id=state.get("agent_run_id"),
        )
    except Exception as exc:
        return {"errors": [f"yield: {exc}"],
                "results": [{"agent": "yield", "output": None, "status": "failed"}]}
    return {"results": [{"agent": "yield", "output": out, "status": "success"}]}


async def inventory_node(state: FarmAgentState) -> dict:
    from app.services.inventory_service import record_inventory
    params_list = state.get("inventory_params") or []
    outputs = []
    for params in params_list:
        try:
            outputs.append(await record_inventory(state["sb"], **params,
                                                  agent_run_id=state.get("agent_run_id")))
        except Exception as exc:
            return {"errors": [f"inventory: {exc}"],
                    "results": [{"agent": "inventory", "output": None, "status": "failed"}]}
    status = "skipped" if not params_list else "success"
    return {"results": [{"agent": "inventory", "output": outputs, "status": status}]}


async def demand_matching_node(state: FarmAgentState) -> dict:
    from app.agents.demand_matching import run_demand_matching
    requests = state.get("demand_requests") or []
    outputs = []
    for demand in requests:
        try:
            outputs.append(await run_demand_matching(demand, state["sb"],
                                                     agent_run_id=state.get("agent_run_id")))
        except Exception as exc:
            return {"errors": [f"demand_matching: {exc}"],
                    "results": [{"agent": "demand_matching", "output": None, "status": "failed"}]}
    status = "skipped" if not requests else "success"
    return {"results": [{"agent": "demand_matching", "output": outputs, "status": status}]}


async def next_season_node(state: FarmAgentState) -> dict:
    from app.services.next_season_service import run_next_season
    try:
        out = await run_next_season(state["sb"], state["farm_id"],
                                    agent_run_id=state.get("agent_run_id"))
    except Exception as exc:
        return {"errors": [f"next_season: {exc}"],
                "results": [{"agent": "next_season", "output": None, "status": "failed"}]}
    return {"results": [{"agent": "next_season", "output": out, "status": "success" if out else "unavailable"}]}


async def supervisor_node(state: FarmAgentState) -> dict:
    from app.services.supervisor_service import run_smart_supervisor
    try:
        out = await run_smart_supervisor(
            state["sb"], state["farm_id"],
            results=state.get("results"),
            agent_run_id=state.get("agent_run_id"),
        )
    except Exception as exc:
        out = None
        return {"results": [{"agent": "smart_supervisor", "output": out, "status": "failed"}],
                "errors": [f"smart_supervisor: {exc}"]}
    return {"results": [{"agent": "smart_supervisor", "output": out,
                         "status": "success" if out else "unavailable"}]}


async def impact_node(state: FarmAgentState) -> dict:
    from app.services.impact_service import record_impact_metrics
    try:
        out = await record_impact_metrics(
            state["sb"], state["farm_id"],
            (state.get("context") or {}).get("farmer_id") or state.get("farmer_id"),
            state.get("agent_run_id"),
            results=state.get("results"),
            context=state.get("context"),
        )
    except Exception as exc:
        return {"errors": [f"impact: {exc}"],
                "results": [{"agent": "impact", "output": None, "status": "failed"}]}
    return {"results": [{"agent": "impact", "output": out,
                         "status": "success" if out else "skipped"}]}


def build_graph():
    graph = StateGraph(FarmAgentState)
    graph.add_node("collect_context", collect_context)
    graph.add_node("irrigation", irrigation_node)
    graph.add_node("crop_health", crop_health_node)
    graph.add_node("yield", yield_node)
    graph.add_node("inventory", inventory_node)
    graph.add_node("demand_matching", demand_matching_node)
    graph.add_node("next_season", next_season_node)
    graph.add_node("supervisor", supervisor_node)
    graph.add_node("impact", impact_node)

    graph.add_edge(START, "collect_context")
    for node in ("irrigation", "crop_health", "yield", "inventory", "demand_matching", "next_season"):
        graph.add_edge("collect_context", node)
    for node in ("irrigation", "crop_health", "yield", "inventory", "demand_matching", "next_season"):
        graph.add_edge(node, "supervisor")
    graph.add_edge("supervisor", "impact")
    graph.add_edge("impact", END)
    return graph.compile()


async def run_farm_graph(
    sb,
    farm_id: str,
    farmer_id: str | None = None,
    image_ctx: dict | None = None,
    inventory_params: list | None = None,
    demand_requests: list | None = None,
) -> dict:
    """Run the whole farm-agent graph and return {context, results, errors}."""
    app = build_graph()
    return await app.ainvoke({
        "sb": sb,
        "farm_id": farm_id,
        "farmer_id": farmer_id,
        "agent_run_id": str(uuid.uuid4()),
        "image_ctx": image_ctx,
        "inventory_params": inventory_params or [],
        "demand_requests": demand_requests or [],
    })
