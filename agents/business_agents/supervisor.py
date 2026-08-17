from __future__ import annotations

from datetime import date

from .crop_planning_advisor import CropPlanningAdvisor
from .demand_matching_agent import DemandMatchingAgent
from .inventory_agent import InventoryAgent
from .models import (
    BusinessReview,
    BuyerDemand,
    CropPerformance,
    CropPlanResult,
    DemandMatchResult,
    FarmSideSignal,
    InventoryBatch,
    InventoryStatus,
    WeatherSnapshot,
)


class BusinessSupervisorAgent:
    def __init__(
        self,
        inventory_agent: InventoryAgent | None = None,
        demand_matching_agent: DemandMatchingAgent | None = None,
        crop_planning_advisor: CropPlanningAdvisor | None = None,
    ) -> None:
        self.inventory_agent = inventory_agent or InventoryAgent()
        self.demand_matching_agent = demand_matching_agent or DemandMatchingAgent()
        self.crop_planning_advisor = crop_planning_advisor or CropPlanningAdvisor()

    def review_inventory(
        self,
        batches: list[InventoryBatch],
        weather_by_crop: dict[str, WeatherSnapshot],
        today: date | None = None,
    ) -> tuple[InventoryStatus, ...]:
        return self.inventory_agent.review_inventory(batches, weather_by_crop, today)

    def match_buyers(
        self,
        inventory_statuses: list[InventoryStatus] | tuple[InventoryStatus, ...],
        buyer_demands: list[BuyerDemand],
        transport_weather: WeatherSnapshot | None = None,
    ) -> tuple[DemandMatchResult, ...]:
        return tuple(
            self.demand_matching_agent.recommend_top_matches(
                inventory=status,
                buyer_demands=buyer_demands,
                transport_weather=transport_weather,
            )
            for status in inventory_statuses
        )

    def plan_next_season(
        self,
        history: list[CropPerformance],
        farm_side_signals: list[FarmSideSignal] | None = None,
    ) -> CropPlanResult:
        return self.crop_planning_advisor.recommend_crops(history, farm_side_signals)

    def full_review(
        self,
        batches: list[InventoryBatch],
        weather_by_crop: dict[str, WeatherSnapshot],
        buyer_demands: list[BuyerDemand],
        crop_history: list[CropPerformance],
        farm_side_signals: list[FarmSideSignal] | None = None,
        today: date | None = None,
    ) -> BusinessReview:
        inventory = self.review_inventory(batches, weather_by_crop, today)
        demand_matches = self.match_buyers(inventory, buyer_demands, weather_by_crop.get("default"))
        crop_plan = self.plan_next_season(crop_history, farm_side_signals)
        return BusinessReview(
            inventory=inventory,
            demand_matches=demand_matches,
            crop_plan=crop_plan,
        )
