from __future__ import annotations

from .crop_profiles import normalize_crop_name
from .models import CropPerformance, CropPlanRecommendation, CropPlanResult, FarmSideSignal


class CropPlanningAdvisor:
    def recommend_crops(
        self,
        history: list[CropPerformance],
        farm_side_signals: list[FarmSideSignal] | None = None,
        limit: int = 3,
    ) -> CropPlanResult:
        if not history:
            return CropPlanResult(
                recommendations=tuple(),
                message="No sales history available for crop planning.",
                farm_side_inputs_used=False,
            )

        signal_map = {
            normalize_crop_name(signal.crop): signal
            for signal in farm_side_signals or []
        }
        farm_inputs_used = bool(signal_map)
        ranked = [
            (self._score(performance, signal_map.get(normalize_crop_name(performance.crop))), performance)
            for performance in history
        ]
        ranked.sort(key=lambda item: item[0], reverse=True)

        selected = ranked[:limit]
        mix = self._suggest_mix([score for score, _ in selected])
        recommendations = tuple(
            self._to_recommendation(index + 1, performance, signal_map.get(normalize_crop_name(performance.crop)), mix[index])
            for index, (_, performance) in enumerate(selected)
        )

        return CropPlanResult(
            recommendations=recommendations,
            message="Next-season crop recommendations prepared for testing.",
            farm_side_inputs_used=farm_inputs_used,
        )

    def _score(self, performance: CropPerformance, signal: FarmSideSignal | None) -> float:
        profit_per_kg = performance.avg_price_per_kg - performance.production_cost_per_kg
        waste_ratio = performance.unsold_or_waste_kg / max(performance.sales_kg + performance.unsold_or_waste_kg, 1)
        demand_factor = 1 + (performance.demand_growth_pct / 100)
        market_factor = 1 + (performance.market_price_trend_pct / 100)
        score = profit_per_kg * demand_factor * market_factor
        score -= waste_ratio * max(performance.avg_price_per_kg, 1) * 0.45

        if signal:
            if signal.expected_yield_kg is not None and signal.yield_confidence is not None:
                score += min(signal.expected_yield_kg / 1000, 2.5) * signal.yield_confidence
            if signal.soil_suitability is not None:
                score += (signal.soil_suitability - 0.5) * 2
            if signal.water_availability is not None:
                score += (signal.water_availability - 0.5)
            if signal.disease_risk is not None:
                score -= signal.disease_risk * 1.5

        return score

    def _suggest_mix(self, scores: list[float]) -> list[int | None]:
        if not scores:
            return []
        positive_scores = [max(score, 0.1) for score in scores]
        total = sum(positive_scores)
        raw = [round(score / total * 100) for score in positive_scores]
        diff = 100 - sum(raw)
        if raw:
            raw[0] += diff
        return raw

    def _to_recommendation(
        self,
        rank: int,
        performance: CropPerformance,
        signal: FarmSideSignal | None,
        suggested_mix: int | None,
    ) -> CropPlanRecommendation:
        profit_per_kg = round(performance.avg_price_per_kg - performance.production_cost_per_kg, 2)
        waste_ratio = performance.unsold_or_waste_kg / max(performance.sales_kg + performance.unsold_or_waste_kg, 1)
        reasons = self._reason_labels(performance, profit_per_kg, waste_ratio, signal)

        return CropPlanRecommendation(
            rank=rank,
            crop=performance.crop,
            expected_profit_per_kg=profit_per_kg,
            demand_outlook=self._demand_outlook(performance.demand_growth_pct),
            waste_risk=self._waste_risk(waste_ratio),
            planning_risk=self._planning_risk(waste_ratio, signal),
            recommendation=self._recommendation_text(performance, waste_ratio, signal),
            reason_labels=tuple(reasons),
            suggested_crop_mix_pct=suggested_mix,
        )

    def _reason_labels(
        self,
        performance: CropPerformance,
        profit_per_kg: float,
        waste_ratio: float,
        signal: FarmSideSignal | None,
    ) -> list[str]:
        reasons = []
        if profit_per_kg > 0:
            reasons.append("Positive profit history")
        if performance.demand_growth_pct >= 8:
            reasons.append("Demand is rising")
        if performance.market_price_trend_pct >= 5:
            reasons.append("Market price improving")
        if waste_ratio <= 0.12:
            reasons.append("Low previous waste")
        if signal and signal.yield_confidence and signal.yield_confidence >= 0.75:
            reasons.append("Yield prediction available")
        if signal and signal.soil_suitability and signal.soil_suitability >= 0.7:
            reasons.append("Good soil suitability")
        return reasons or ["Useful crop to test in planning"]

    def _demand_outlook(self, demand_growth_pct: float) -> str:
        if demand_growth_pct >= 12:
            return "strong growth"
        if demand_growth_pct >= 3:
            return "moderate growth"
        if demand_growth_pct >= -3:
            return "stable"
        return "declining"

    def _waste_risk(self, waste_ratio: float) -> str:
        if waste_ratio <= 0.1:
            return "low"
        if waste_ratio <= 0.25:
            return "medium"
        return "high"

    def _planning_risk(self, waste_ratio: float, signal: FarmSideSignal | None) -> str:
        risk = 0
        if waste_ratio > 0.25:
            risk += 1
        if signal and signal.disease_risk and signal.disease_risk > 0.55:
            risk += 1
        if signal and signal.water_availability is not None and signal.water_availability < 0.4:
            risk += 1
        return ["low", "medium", "high", "high"][risk]

    def _recommendation_text(
        self,
        performance: CropPerformance,
        waste_ratio: float,
        signal: FarmSideSignal | None,
    ) -> str:
        if waste_ratio > 0.25:
            return "Plant cautiously unless buyer demand is confirmed before harvest."
        if signal and signal.disease_risk and signal.disease_risk > 0.55:
            return "Consider only with disease-control planning."
        if performance.demand_growth_pct >= 8:
            return "Good candidate for next season based on demand and sales history."
        return "Good candidate for testing with a controlled crop mix."
