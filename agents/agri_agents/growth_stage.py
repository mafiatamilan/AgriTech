from __future__ import annotations

from datetime import date

from .crop_calendars import get_crop_calendar
from .models import ConfidenceLevel, CropCalendar, CropFieldContext, GrowthStage, GrowthStageEstimate


class GrowthStageEstimator:
    def __init__(self, crop_calendars: dict[str, CropCalendar] | None = None) -> None:
        self.crop_calendars = crop_calendars

    def estimate(self, context: CropFieldContext, today: date | None = None) -> GrowthStageEstimate:
        if context.growth_stage and context.growth_stage != GrowthStage.UNKNOWN:
            return GrowthStageEstimate(
                stage=context.growth_stage,
                source="provided",
                confidence=ConfidenceLevel.HIGH,
            )

        if not context.planting_date:
            return GrowthStageEstimate(
                stage=GrowthStage.UNKNOWN,
                source="missing planting date",
                confidence=ConfidenceLevel.UNCERTAIN,
            )

        today = today or date.today()
        days_after_planting = max(0, (today - context.planting_date).days)
        calendar = get_crop_calendar(context.crop, self.crop_calendars)

        if calendar is None:
            return GrowthStageEstimate(
                stage=GrowthStage.UNKNOWN,
                source="missing crop calendar",
                confidence=ConfidenceLevel.UNCERTAIN,
                days_after_planting=days_after_planting,
            )

        stage = self._stage_from_days(calendar, days_after_planting)
        return GrowthStageEstimate(
            stage=stage,
            source="estimated from planting date",
            confidence=ConfidenceLevel.MEDIUM,
            days_after_planting=days_after_planting,
        )

    def _stage_from_days(self, calendar: CropCalendar, days: int) -> GrowthStage:
        if days <= calendar.germination_days:
            return GrowthStage.GERMINATION
        if days <= calendar.seedling_days:
            return GrowthStage.SEEDLING
        if days <= calendar.vegetative_days:
            return GrowthStage.VEGETATIVE
        if days <= calendar.flowering_days:
            return GrowthStage.FLOWERING
        if days <= calendar.fruiting_days:
            return GrowthStage.FRUITING
        return GrowthStage.MATURITY
