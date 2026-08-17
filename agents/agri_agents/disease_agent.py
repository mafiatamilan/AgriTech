from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .disease_remedies import DiseaseRemedyAdvisor
from .models import ConfidenceLevel, ModelPrediction, PlantDiseaseDiagnosis


class PlantDiseaseModelAdapter(Protocol):
    def predict(self, image_path: str, crop_hint: str | None = None) -> ModelPrediction:
        """Return a PlantVillage-style label and confidence."""


class StaticPlantVillageModelAdapter:
    """Test adapter. Replace with a real PlantVillage model adapter in backend/model service."""

    def __init__(self, label: str, confidence: float) -> None:
        self.label = label
        self.confidence = confidence

    def predict(self, image_path: str, crop_hint: str | None = None) -> ModelPrediction:
        return ModelPrediction(label=self.label, confidence=self.confidence)


class PlantVillageLabelParser:
    def parse(self, label: str) -> tuple[str, str, bool]:
        raw = label.strip()
        if not raw:
            return "unknown", "unknown", False

        if "___" in raw:
            crop_raw, disease_raw = raw.split("___", maxsplit=1)
        else:
            cleaned = raw.replace("__", " ").replace("_", " ")
            parts = cleaned.split(maxsplit=1)
            crop_raw = parts[0] if parts else "unknown"
            disease_raw = parts[1] if len(parts) > 1 else "unknown"

        crop = self._humanize(crop_raw)
        disease = self._humanize(disease_raw)
        is_healthy = "healthy" in disease
        if is_healthy:
            disease = "healthy"
        return crop, disease, is_healthy

    def _humanize(self, value: str) -> str:
        return (
            value.replace("_", " ")
            .replace(",", "")
            .replace("(", "")
            .replace(")", "")
            .strip()
            .lower()
        )


class DiseasePredictionAgent:
    def __init__(
        self,
        model_adapter: PlantDiseaseModelAdapter,
        remedy_advisor: DiseaseRemedyAdvisor | None = None,
        label_parser: PlantVillageLabelParser | None = None,
    ) -> None:
        self.model_adapter = model_adapter
        self.remedy_advisor = remedy_advisor or DiseaseRemedyAdvisor()
        self.label_parser = label_parser or PlantVillageLabelParser()

    def analyze_image(self, image_path: str, crop_hint: str | None = None) -> PlantDiseaseDiagnosis:
        self._validate_image_path(image_path)
        prediction = self.model_adapter.predict(image_path=image_path, crop_hint=crop_hint)
        crop, disease, is_healthy = self.label_parser.parse(prediction.label)
        if crop_hint and crop == "unknown":
            crop = crop_hint.strip().lower()

        confidence_level = self._confidence_level(prediction.confidence)
        if crop_hint and self._crop_conflicts(crop_hint, crop):
            return PlantDiseaseDiagnosis(
                crop=crop,
                disease="uncertain",
                is_healthy=False,
                confidence_level=ConfidenceLevel.UNCERTAIN,
                severity="uncertain",
                recommendation=(
                    "Model prediction does not match the selected crop. "
                    "Check the crop selection or use a model trained for this crop."
                ),
                remedies=tuple(),
                prevention=tuple(),
                retake_image=True,
                reason_labels=("Crop mismatch", "Retake image or change crop/model"),
            )

        if confidence_level == ConfidenceLevel.UNCERTAIN:
            return PlantDiseaseDiagnosis(
                crop=crop,
                disease="uncertain",
                is_healthy=False,
                confidence_level=confidence_level,
                severity="uncertain",
                recommendation="Image is unclear. Retake the photo in daylight with the affected leaf centered.",
                remedies=tuple(),
                prevention=tuple(),
                retake_image=True,
                reason_labels=("Low model confidence", "Retake image"),
            )

        remedy = self.remedy_advisor.lookup(crop, disease)
        recommendation = "Crop looks healthy in this image." if is_healthy else str(remedy["remedies"][0])
        reasons = ["PlantVillage model prediction"]
        if confidence_level == ConfidenceLevel.HIGH:
            reasons.append("High confidence")
        if is_healthy:
            reasons.append("No disease detected")

        return PlantDiseaseDiagnosis(
            crop=crop,
            disease=disease,
            is_healthy=is_healthy,
            confidence_level=confidence_level,
            severity=str(remedy["severity"]),
            recommendation=recommendation,
            remedies=tuple(remedy["remedies"]),
            prevention=tuple(remedy["prevention"]),
            retake_image=False,
            reason_labels=tuple(reasons),
        )

    def _confidence_level(self, confidence: float) -> ConfidenceLevel:
        if confidence >= 0.8:
            return ConfidenceLevel.HIGH
        if confidence >= 0.6:
            return ConfidenceLevel.MEDIUM
        return ConfidenceLevel.UNCERTAIN

    def _validate_image_path(self, image_path: str) -> None:
        if not image_path:
            raise ValueError("image_path is required.")
        suffix = Path(image_path).suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
            raise ValueError("Plant image must be a .jpg, .jpeg, .png, or .webp file.")

    def _crop_conflicts(self, crop_hint: str, predicted_crop: str) -> bool:
        hint = self.label_parser._humanize(crop_hint)
        predicted = self.label_parser._humanize(predicted_crop)
        if hint in {"unknown", ""} or predicted in {"unknown", ""}:
            return False
        aliases = {
            "corn": {"corn", "corn maize", "maize"},
            "maize": {"corn", "corn maize", "maize"},
            "bell pepper": {"bell pepper", "pepper bell", "pepper"},
            "pepper": {"bell pepper", "pepper bell", "pepper"},
        }
        hint_values = aliases.get(hint, {hint})
        predicted_values = aliases.get(predicted, {predicted})
        return hint_values.isdisjoint(predicted_values)
