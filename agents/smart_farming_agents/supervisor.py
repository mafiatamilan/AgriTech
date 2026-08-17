from __future__ import annotations

from datetime import date

from agri_agents import AgriSupervisorAgent
from agri_agents.models import (
    AgriReview,
    CropFieldContext,
    WeatherSnapshot as AgriWeatherSnapshot,
    YieldPredictionSignal,
)
from business_agents import BusinessSupervisorAgent
from business_agents.models import (
    BusinessReview,
    BuyerDemand,
    CropPerformance,
    FarmSideSignal,
    InventoryBatch,
    Urgency,
    WeatherSnapshot as BusinessWeatherSnapshot,
)

from .models import SmartFarmingReview


class SmartFarmingSupervisorAgent:
    """Top-level coordinator for farm-side and business-side agents.

    The backend can use this for dashboard/all-insights flows while still calling
    `AgriSupervisorAgent` and `BusinessSupervisorAgent` directly for narrower APIs.
    """

    def __init__(
        self,
        agri_supervisor: AgriSupervisorAgent | None = None,
        business_supervisor: BusinessSupervisorAgent | None = None,
    ) -> None:
        self.agri_supervisor = agri_supervisor or AgriSupervisorAgent()
        self.business_supervisor = business_supervisor or BusinessSupervisorAgent()

    def review_agri(
        self,
        context: CropFieldContext,
        weather: AgriWeatherSnapshot,
        image_path: str | None = None,
        crop_hint: str | None = None,
        yield_prediction: YieldPredictionSignal | None = None,
        today: date | None = None,
    ) -> AgriReview:
        return self.agri_supervisor.full_review(
            context=context,
            weather=weather,
            image_path=image_path,
            crop_hint=crop_hint,
            yield_prediction=yield_prediction,
            today=today,
        )

    def review_business(
        self,
        batches: list[InventoryBatch],
        weather_by_crop: dict[str, BusinessWeatherSnapshot],
        buyer_demands: list[BuyerDemand],
        crop_history: list[CropPerformance],
        farm_side_signals: list[FarmSideSignal] | None = None,
        today: date | None = None,
    ) -> BusinessReview:
        return self.business_supervisor.full_review(
            batches=batches,
            weather_by_crop=weather_by_crop,
            buyer_demands=buyer_demands,
            crop_history=crop_history,
            farm_side_signals=farm_side_signals,
            today=today,
        )

    def full_review(
        self,
        agri_context: CropFieldContext | None = None,
        agri_weather: AgriWeatherSnapshot | None = None,
        image_path: str | None = None,
        crop_hint: str | None = None,
        yield_prediction: YieldPredictionSignal | None = None,
        business_batches: list[InventoryBatch] | None = None,
        business_weather_by_crop: dict[str, BusinessWeatherSnapshot] | None = None,
        buyer_demands: list[BuyerDemand] | None = None,
        crop_history: list[CropPerformance] | None = None,
        farm_side_signals: list[FarmSideSignal] | None = None,
        today: date | None = None,
    ) -> SmartFarmingReview:
        agri_review = None
        if agri_context and agri_weather:
            agri_review = self.review_agri(
                context=agri_context,
                weather=agri_weather,
                image_path=image_path,
                crop_hint=crop_hint,
                yield_prediction=yield_prediction,
                today=today,
            )

        business_review = None
        if business_batches is not None and business_weather_by_crop is not None:
            business_review = self.review_business(
                batches=business_batches,
                weather_by_crop=business_weather_by_crop,
                buyer_demands=buyer_demands or [],
                crop_history=crop_history or [],
                farm_side_signals=farm_side_signals,
                today=today,
            )

        return SmartFarmingReview(
            agri_review=agri_review,
            business_review=business_review,
            alerts=self._alerts(agri_review, business_review),
            next_actions=self._next_actions(agri_review, business_review),
        )

    def _alerts(
        self,
        agri_review: AgriReview | None,
        business_review: BusinessReview | None,
    ) -> tuple[str, ...]:
        alerts: list[str] = []
        if agri_review:
            alerts.extend(agri_review.alerts)

        if business_review:
            for inventory in business_review.inventory:
                urgency = inventory.shelf_life.urgency
                if urgency in {Urgency.HIGH, Urgency.URGENT, Urgency.EXPIRED_RISK}:
                    alerts.append(
                        f"{inventory.crop.title()} inventory needs attention: "
                        f"{inventory.shelf_life.recommendation}"
                    )
            for match in business_review.demand_matches:
                if match.top_matches:
                    alerts.append(
                        f"{match.crop.title()} has {len(match.top_matches)} buyer options ready."
                    )

        return tuple(dict.fromkeys(alerts))

    def _next_actions(
        self,
        agri_review: AgriReview | None,
        business_review: BusinessReview | None,
    ) -> tuple[str, ...]:
        actions: list[str] = []

        if agri_review and agri_review.disease:
            disease = agri_review.disease
            if disease.retake_image:
                actions.append("Retake plant image before giving treatment advice.")
            elif not disease.is_healthy:
                actions.append(f"Treat or inspect {disease.crop} for {disease.disease}.")

        if agri_review and agri_review.irrigation and agri_review.irrigation.irrigation_needed:
            actions.append(agri_review.irrigation.recommendation)

        if business_review:
            for match in business_review.demand_matches:
                if match.top_matches:
                    top = match.top_matches[0]
                    actions.append(
                        f"Show farmer top buyer option for {match.crop}: {top.buyer_name}."
                    )

            if business_review.crop_plan and business_review.crop_plan.recommendations:
                top_crop = business_review.crop_plan.recommendations[0].crop
                actions.append(f"Use {top_crop} as the leading next-season crop planning option.")

        return tuple(dict.fromkeys(actions))
