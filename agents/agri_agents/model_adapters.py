from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

from .models import ModelPrediction
from .pddd_labels import PDDD_NORMALIZATION_MEAN, PDDD_NORMALIZATION_STD, load_pddd_labels
from .plant_village_labels import load_labels


class PlantVillageImagePreprocessor:
    def __init__(self, image_size: tuple[int, int] = (224, 224), rescale: bool = True) -> None:
        self.image_size = image_size
        self.rescale = rescale

    def preprocess(self, image_path: str) -> np.ndarray:
        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Image not found: {image_path}")

        with Image.open(path) as image:
            image = image.convert("RGB").resize(self.image_size)
            array = np.asarray(image, dtype=np.float32)

        if self.rescale:
            array = array / 255.0
        return np.expand_dims(array, axis=0)


class PDDDImagePreprocessor:
    def __init__(self, image_size: int = 224) -> None:
        self.image_size = image_size

    def preprocess(self, image_path: str) -> Any:
        try:
            import torch
        except ImportError as exc:
            raise ImportError(
                "PyTorch is required for PDDDPlantDiseaseModelAdapter. "
                "Install torch in the backend/runtime environment."
            ) from exc

        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Image not found: {image_path}")

        with Image.open(path) as image:
            image = image.convert("RGB")
            image = self._resize_short_side(image, 256)
            image = self._center_crop(image, self.image_size)
            array = np.asarray(image, dtype=np.float32) / 255.0

        mean = np.asarray(PDDD_NORMALIZATION_MEAN, dtype=np.float32)
        std = np.asarray(PDDD_NORMALIZATION_STD, dtype=np.float32)
        array = (array - mean) / std
        array = np.transpose(array, (2, 0, 1))
        return torch.from_numpy(array).unsqueeze(0)

    def _resize_short_side(self, image: Image.Image, short_side: int) -> Image.Image:
        width, height = image.size
        if width <= height:
            new_width = short_side
            new_height = round(height * short_side / width)
        else:
            new_height = short_side
            new_width = round(width * short_side / height)
        return image.resize((new_width, new_height))

    def _center_crop(self, image: Image.Image, size: int) -> Image.Image:
        width, height = image.size
        left = max(0, (width - size) // 2)
        top = max(0, (height - size) // 2)
        return image.crop((left, top, left + size, top + size))


class KerasPlantVillageModelAdapter:
    """Loads a Keras/TensorFlow PlantVillage image classification model.

    Supports `.keras`, `.h5`, and SavedModel-compatible paths when TensorFlow is
    installed in the backend runtime.
    """

    def __init__(
        self,
        model_path: str,
        labels_path: str | None = None,
        image_size: tuple[int, int] = (224, 224),
    ) -> None:
        self.model_path = model_path
        self.labels = load_labels(labels_path)
        self.preprocessor = PlantVillageImagePreprocessor(image_size=image_size)
        self._model: Any | None = None

    def predict(self, image_path: str, crop_hint: str | None = None) -> ModelPrediction:
        model = self._load_model()
        batch = self.preprocessor.preprocess(image_path)
        prediction = model.predict(batch, verbose=0)
        return self._to_prediction(prediction)

    def _load_model(self) -> Any:
        if self._model is None:
            try:
                from tensorflow import keras
            except ImportError as exc:
                raise ImportError(
                    "TensorFlow is required for KerasPlantVillageModelAdapter. "
                    "Install tensorflow in the backend runtime or use TFLitePlantVillageModelAdapter."
                ) from exc
            self._model = keras.models.load_model(self.model_path)
        return self._model

    def _to_prediction(self, prediction: Any) -> ModelPrediction:
        scores = np.asarray(prediction).reshape(-1)
        if len(scores) != len(self.labels):
            raise ValueError(f"Model returned {len(scores)} scores but {len(self.labels)} labels are configured.")
        index = int(np.argmax(scores))
        return ModelPrediction(label=self.labels[index], confidence=float(scores[index]))


class TFLitePlantVillageModelAdapter:
    """Loads a TensorFlow Lite PlantVillage model.

    This is the better path if your team wants mobile/offline inference or a small
    backend inference container.
    """

    def __init__(
        self,
        model_path: str,
        labels_path: str | None = None,
        image_size: tuple[int, int] = (224, 224),
    ) -> None:
        self.model_path = model_path
        self.labels = load_labels(labels_path)
        self.preprocessor = PlantVillageImagePreprocessor(image_size=image_size)
        self._interpreter: Any | None = None

    def predict(self, image_path: str, crop_hint: str | None = None) -> ModelPrediction:
        interpreter = self._load_interpreter()
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()
        batch = self.preprocessor.preprocess(image_path)
        expected_dtype = input_details[0]["dtype"]
        if expected_dtype != np.float32:
            batch = (batch * 255).astype(expected_dtype)

        interpreter.set_tensor(input_details[0]["index"], batch.astype(expected_dtype))
        interpreter.invoke()
        prediction = interpreter.get_tensor(output_details[0]["index"])
        return self._to_prediction(prediction)

    def _load_interpreter(self) -> Any:
        if self._interpreter is None:
            try:
                from tflite_runtime.interpreter import Interpreter
            except ImportError:
                try:
                    from tensorflow.lite.python.interpreter import Interpreter
                except ImportError as exc:
                    raise ImportError(
                        "TensorFlow Lite runtime is required for TFLitePlantVillageModelAdapter. "
                        "Install tflite-runtime or tensorflow in the backend runtime."
                    ) from exc

            self._interpreter = Interpreter(model_path=self.model_path)
            self._interpreter.allocate_tensors()
        return self._interpreter

    def _to_prediction(self, prediction: Any) -> ModelPrediction:
        scores = np.asarray(prediction).reshape(-1)
        if len(scores) != len(self.labels):
            raise ValueError(f"Model returned {len(scores)} scores but {len(self.labels)} labels are configured.")
        index = int(np.argmax(scores))
        return ModelPrediction(label=self.labels[index], confidence=float(scores[index]))


class RoboflowPlantVillageModelAdapter:
    """Uses Roboflow Hosted/Serverless API for PlantVillage-style inference.

    This adapter keeps the same contract as local Keras/TFLite adapters. The API
    key should live in the backend environment, never in the mobile app.
    """

    def __init__(
        self,
        api_key: str,
        model_id: str,
        api_url: str = "https://serverless.roboflow.com",
        client: Any | None = None,
    ) -> None:
        if not api_key:
            raise ValueError("api_key is required for Roboflow inference.")
        if not model_id:
            raise ValueError("model_id is required for Roboflow inference.")

        self.api_key = api_key
        self.model_id = model_id
        self.api_url = api_url
        self._client = client

    def predict(self, image_path: str, crop_hint: str | None = None) -> ModelPrediction:
        client = self._load_client()
        result = client.infer(image_path, model_id=self.model_id)
        prediction = self._extract_prediction(result)

        label = prediction["label"]
        if crop_hint and "___" not in label and crop_hint.lower() not in label.lower():
            label = f"{crop_hint}___{label}"

        return ModelPrediction(label=label, confidence=prediction["confidence"])

    def _load_client(self) -> Any:
        if self._client is None:
            try:
                from inference_sdk import InferenceHTTPClient
            except ImportError as exc:
                raise ImportError(
                    "inference-sdk is required for RoboflowPlantVillageModelAdapter. "
                    "Install it in the backend runtime with: pip install inference-sdk"
                ) from exc

            self._client = InferenceHTTPClient(
                api_url=self.api_url,
                api_key=self.api_key,
            )
        return self._client

    def _extract_prediction(self, result: Any) -> dict[str, Any]:
        if not isinstance(result, dict):
            raise ValueError("Roboflow result must be a dictionary.")

        if "top" in result:
            label = str(result["top"])
            confidence = float(result.get("confidence", self._confidence_from_predictions(result, label)))
            return {"label": label, "confidence": confidence}

        predictions = result.get("predictions")
        if isinstance(predictions, list) and predictions:
            best = max(predictions, key=lambda item: float(item.get("confidence", 0.0)))
            label = str(best.get("class") or best.get("class_name") or best.get("label") or "unknown")
            confidence = float(best.get("confidence", 0.0))
            return {"label": label, "confidence": confidence}

        if isinstance(predictions, dict) and predictions:
            normalized = []
            for label, value in predictions.items():
                confidence = value.get("confidence", 0.0) if isinstance(value, dict) else value
                normalized.append({"label": str(label), "confidence": float(confidence)})
            return max(normalized, key=lambda item: item["confidence"])

        raise ValueError("Roboflow result did not contain a usable prediction.")

    def _confidence_from_predictions(self, result: dict[str, Any], label: str) -> float:
        predictions = result.get("predictions")
        if isinstance(predictions, dict) and label in predictions:
            value = predictions[label]
            return float(value.get("confidence", 0.0) if isinstance(value, dict) else value)
        if isinstance(predictions, list):
            for item in predictions:
                item_label = item.get("class") or item.get("class_name") or item.get("label")
                if item_label == label:
                    return float(item.get("confidence", 0.0))
        return 0.0


class PDDDPlantDiseaseModelAdapter:
    """Loads a PDDD PyTorch MobileNet checkpoint for local inference.

    Use `architecture="mobilenet_v3_large"` for the recommended lightweight PDDD
    MobileNetV3-Large checkpoint. If the `.pth` file contains a full PyTorch
    module, the adapter can load it without constructing an architecture.
    """

    def __init__(
        self,
        model_path: str,
        labels_path: str,
        architecture: str = "mobilenet_v3_large",
        device: str | None = None,
    ) -> None:
        self.model_path = model_path
        self.labels = load_pddd_labels(labels_path)
        self.architecture = architecture
        self.device = device
        self.preprocessor = PDDDImagePreprocessor()
        self._model: Any | None = None

    def predict(self, image_path: str, crop_hint: str | None = None) -> ModelPrediction:
        torch = self._torch()
        model = self._load_model()
        batch = self.preprocessor.preprocess(image_path).to(self._device(torch))

        with torch.no_grad():
            output = model(batch)
            if isinstance(output, (tuple, list)):
                output = output[0]
            scores = torch.nn.functional.softmax(output[0], dim=0)
            confidence, index = torch.max(scores, dim=0)

        return ModelPrediction(
            label=self.labels[int(index.item())],
            confidence=float(confidence.item()),
        )

    def _load_model(self) -> Any:
        if self._model is not None:
            return self._model

        torch = self._torch()
        device = self._device(torch)
        checkpoint = torch.load(self.model_path, map_location=device)

        if hasattr(checkpoint, "eval") and callable(checkpoint.eval):
            model = checkpoint
        else:
            state_dict = self._extract_state_dict(checkpoint)
            model = self._build_model(len(self.labels))
            model.load_state_dict(state_dict)

        model.to(device)
        model.eval()
        self._model = model
        return model

    def _extract_state_dict(self, checkpoint: Any) -> Any:
        if isinstance(checkpoint, dict):
            for key in ("state_dict", "model_state_dict", "model"):
                if key in checkpoint:
                    return checkpoint[key]
        return checkpoint

    def _build_model(self, num_classes: int) -> Any:
        try:
            from torchvision import models
        except ImportError as exc:
            raise ImportError(
                "torchvision is required when a PDDD checkpoint contains only a state_dict. "
                "Install torchvision or use a .pth file that stores the full model."
            ) from exc

        if self.architecture != "mobilenet_v3_large":
            raise ValueError("Only architecture='mobilenet_v3_large' is currently wired for PDDD.")

        try:
            model = models.mobilenet_v3_large(weights=None, num_classes=num_classes)
        except TypeError:
            model = models.mobilenet_v3_large(pretrained=False, num_classes=num_classes)
        return model

    def _torch(self) -> Any:
        try:
            import torch
        except ImportError as exc:
            raise ImportError(
                "PyTorch is required for PDDDPlantDiseaseModelAdapter. "
                "Install torch in the backend/runtime environment."
            ) from exc
        return torch

    def _device(self, torch: Any) -> Any:
        if self.device:
            return torch.device(self.device)
        return torch.device("cuda" if torch.cuda.is_available() else "cpu")
