# Farm-Side Agents

Standalone farm-side agent logic for the smart farming multi-agent platform.

The package contains:

- `DiseasePredictionAgent`: uses a PlantVillage-style model adapter and converts model labels into farmer-facing diagnosis, confidence level, remedy, and prevention output.
- `SoilTypeIrrigationAgent`: calculates irrigation need without soil sensors and without root-zone inputs. It uses crop, soil type, growth stage, weather, rainfall, and last irrigation date.
- `AgriSupervisorAgent`: coordinates disease diagnosis, irrigation decisions, and optional yield-prediction output from a separate yield agent.

## PlantVillage Model Integration

The package includes model adapters for real inference:

- `KerasPlantVillageModelAdapter` for `.keras`, `.h5`, or TensorFlow SavedModel paths.
- `TFLitePlantVillageModelAdapter` for `.tflite` models.
- `RoboflowPlantVillageModelAdapter` for Roboflow-hosted models.
- `PDDDPlantDiseaseModelAdapter` for PDDD PyTorch MobileNet checkpoints.

Both adapters expose this method:

```python
predict(image_path: str, crop_hint: str | None = None) -> ModelPrediction
```

The model should return PlantVillage-style labels such as:

```text
Tomato___Late_blight
Potato___healthy
```

The backend/model team can plug in PyTorch, TensorFlow, TFLite, Hugging Face, or any other PlantVillage-trained model behind that adapter.

Example backend usage with a Keras model:

```python
from agri_agents import AgriSupervisorAgent, DiseasePredictionAgent, KerasPlantVillageModelAdapter

model_adapter = KerasPlantVillageModelAdapter(
    model_path="models/plantvillage_model.keras",
)
disease_agent = DiseasePredictionAgent(model_adapter)
supervisor = AgriSupervisorAgent(disease_agent=disease_agent)

diagnosis = supervisor.diagnose_crop_health("uploads/leaf.jpg", crop_hint="tomato")
```

Example backend usage with a TFLite model:

```python
from agri_agents import AgriSupervisorAgent, DiseasePredictionAgent, TFLitePlantVillageModelAdapter

model_adapter = TFLitePlantVillageModelAdapter(
    model_path="models/plantvillage_model.tflite",
)
disease_agent = DiseasePredictionAgent(model_adapter)
supervisor = AgriSupervisorAgent(disease_agent=disease_agent)
```

Example backend usage with Roboflow:

```python
import os
from agri_agents import AgriSupervisorAgent, DiseasePredictionAgent, RoboflowPlantVillageModelAdapter

model_adapter = RoboflowPlantVillageModelAdapter(
    api_key=os.environ["ROBOFLOW_API_KEY"],
    model_id="plantvillage-dataset-ae42p/1",
)
disease_agent = DiseasePredictionAgent(model_adapter)
supervisor = AgriSupervisorAgent(disease_agent=disease_agent)

diagnosis = supervisor.diagnose_crop_health("uploads/leaf.jpg", crop_hint="tomato")
```

Keep the Roboflow API key in the backend environment. Do not send it to the mobile app.

## PDDD MobileNet Integration

Use this when you download a PDDD MobileNet `.pth` checkpoint and the matching `class_indices.json`.

Recommended structure:

```text
smart_farming_agents_clean/
  agri_agents/
  business_agents/
  models/
    pddd_mobilenetv3_large.pth
    class_indices.json
  test_pddd.py
```

Install runtime dependencies in VS Code:

```powershell
py -m pip install torch torchvision pillow numpy
```

Create `test_pddd.py`:

```python
from agri_agents import AgriSupervisorAgent, DiseasePredictionAgent, PDDDPlantDiseaseModelAdapter

model_adapter = PDDDPlantDiseaseModelAdapter(
    model_path="models/pddd_mobilenetv3_large.pth",
    labels_path="models/class_indices.json",
    architecture="mobilenet_v3_large",
)

disease_agent = DiseasePredictionAgent(model_adapter)
supervisor = AgriSupervisorAgent(disease_agent=disease_agent)

diagnosis = supervisor.diagnose_crop_health(
    image_path="leaf.jpg",
    crop_hint="corn",
)

print(diagnosis)
```

Run:

```powershell
py test_pddd.py
```

Important:

- The PDDD label order must match the checkpoint output order.
- Use the downloaded `class_indices.json`; do not manually guess label order.
- If the `.pth` file contains only a `state_dict`, `torchvision` is required to rebuild MobileNetV3-Large.
- If the `.pth` file stores the full PyTorch model, the adapter can load it directly.

If your model was trained with a different class order, pass a label file:

```python
KerasPlantVillageModelAdapter(
    model_path="models/plantvillage_model.keras",
    labels_path="models/labels.txt",
)
```

## Growth Stage

Growth stage is determined in this order:

1. Use `growth_stage` if the app/backend provides it.
2. Estimate from `planting_date` and the crop calendar.
3. Return `unknown` if both are missing.

No root-zone input is used.

## Auto Irrigation

The agent does not publish MQTT directly. If auto irrigation is enabled and watering is needed, it returns:

- `mqtt_command.topic`
- `mqtt_command.payload`

Your backend should publish that payload to the broker.

## Run Tests

```powershell
python -m unittest discover -s tests
```
