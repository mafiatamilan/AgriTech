from __future__ import annotations

from typing import Any

from .models import ModelPrediction


class ViTPlantDiseaseModelAdapter:
    """HuggingFace Vision Transformer for multi-crop disease classification.

    Uses ``wambugu71/crop_leaf_diseases_vit`` by default — a ViT-Tiny model
    fine-tuned on corn, potato, rice, and wheat diseases (14 classes, ~98% acc).
    """

    def __init__(self, model_name: str = "wambugu71/crop_leaf_diseases_vit") -> None:
        self.model_name = model_name
        self._processor: Any | None = None
        self._model: Any | None = None

    def predict(self, image_path: str, crop_hint: str | None = None) -> ModelPrediction:
        from PIL import Image as PILImage

        processor, model = self._load()
        image = PILImage.open(image_path).convert("RGB")
        inputs = processor(images=image, return_tensors="pt")

        torch = self._torch()
        with torch.no_grad():
            outputs = model(**inputs)
            probs = torch.nn.functional.softmax(outputs.logits, dim=1).squeeze()
            confidence, index = torch.max(probs, dim=0)

        label = model.config.id2label[index.item()]
        return ModelPrediction(label=label, confidence=float(confidence.item()))

    def _load(self) -> tuple[Any, Any]:
        if self._model is not None:
            return self._processor, self._model

        from transformers import AutoImageProcessor, AutoModelForImageClassification

        self._processor = AutoImageProcessor.from_pretrained(self.model_name)
        self._model = AutoModelForImageClassification.from_pretrained(self.model_name)
        self._model.eval()
        return self._processor, self._model

    def _torch(self) -> Any:
        try:
            import torch
        except ImportError as exc:
            raise ImportError(
                "PyTorch is required for ViTPlantDiseaseModelAdapter. "
                "Install torch in the backend/runtime environment."
            ) from exc
        return torch
