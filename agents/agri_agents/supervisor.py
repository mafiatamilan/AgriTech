from __future__ import annotations

from datetime import date

from .disease_agent import DiseasePredictionAgent
from .irrigation_agent import SoilTypeIrrigationAgent
from .models import (
    AgriReview,
    CropFieldContext,
    IrrigationDecision,
    PlantDiseaseDiagnosis,
    WeatherSnapshot,
    YieldPredictionSignal,
)


class AgriSupervisorAgent:
    def __init__(
        self,
        disease_agent: DiseasePredictionAgent | None = None,
        irrigation_agent: SoilTypeIrrigationAgent | None = None,
    ) -> None:
        self.disease_agent = disease_agent
        self.irrigation_agent = irrigation_agent or SoilTypeIrrigationAgent()

    def diagnose_crop_health(
        self,
        image_path: str,
        crop_hint: str | None = None,
    ) -> PlantDiseaseDiagnosis:
        if self.disease_agent is None:
            raise ValueError("DiseasePredictionAgent requires a PlantVillage model adapter.")
        return self.disease_agent.analyze_image(image_path=image_path, crop_hint=crop_hint)

    def decide_irrigation(
        self,
        context: CropFieldContext,
        weather: WeatherSnapshot,
        today: date | None = None,
    ) -> IrrigationDecision:
        return self.irrigation_agent.decide(context=context, weather=weather, today=today)

    def full_review(
        self,
        context: CropFieldContext,
        weather: WeatherSnapshot,
        image_path: str | None = None,
        crop_hint: str | None = None,
        yield_prediction: YieldPredictionSignal | None = None,
        today: date | None = None,
    ) -> AgriReview:
        disease = None
        if image_path and self.disease_agent:
            disease = self.diagnose_crop_health(image_path=image_path, crop_hint=crop_hint)

        irrigation = self.decide_irrigation(context=context, weather=weather, today=today)
        alerts = self._alerts(disease, irrigation, yield_prediction)

        return AgriReview(
            disease=disease,
            irrigation=irrigation,
            yield_prediction=yield_prediction,
            alerts=alerts,
        )

    def _alerts(
        self,
        disease: PlantDiseaseDiagnosis | None,
        irrigation: IrrigationDecision,
        yield_prediction: YieldPredictionSignal | None,
    ) -> tuple[str, ...]:
        alerts: list[str] = []
        if disease and not disease.is_healthy and not disease.retake_image:
            alerts.append(f"{disease.crop.title()} {disease.disease} detected. Inspect nearby plants.")
        if disease and disease.retake_image:
            alerts.append("Retake plant image before giving disease treatment advice.")
        if irrigation.irrigation_needed:
            alerts.append(irrigation.recommendation)
        if yield_prediction and yield_prediction.risk_factors:
            alerts.append("Yield risk factors reported: " + ", ".join(yield_prediction.risk_factors))
        return tuple(alerts)
