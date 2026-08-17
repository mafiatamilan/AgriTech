# Smart Farming Agents

Combined standalone agent logic for the smart farming multi-agent platform.

This folder contains both sides:

- `agri_agents/`: farm-side agents
- `business_agents/`: business-side agents
- `smart_farming_agents/`: combined supervisor for both sides
- `tests/`: verification tests for both packages

No backend framework is included. Your backend team can import these packages and expose them through APIs/MQTT.

## Farm-Side Agents

Main entry point:

```python
from agri_agents import AgriSupervisorAgent
```

Included:

- `DiseasePredictionAgent`
- `KerasPlantVillageModelAdapter`
- `PDDDPlantDiseaseModelAdapter`
- `TFLitePlantVillageModelAdapter`
- `RoboflowPlantVillageModelAdapter`
- `SoilTypeIrrigationAgent`
- `AgriSupervisorAgent`

The PlantVillage model file is not bundled. Add it later under a backend-controlled path such as:

```text
models/plantvillage_model.keras
```

or:

```text
models/plantvillage_model.tflite
```

For PDDD MobileNet, add:

```text
models/pddd_mobilenetv3_large.pth
models/class_indices.json
```

Then use:

```python
from agri_agents import DiseasePredictionAgent, PDDDPlantDiseaseModelAdapter

model_adapter = PDDDPlantDiseaseModelAdapter(
    model_path="models/pddd_mobilenetv3_large.pth",
    labels_path="models/class_indices.json",
)

disease_agent = DiseasePredictionAgent(model_adapter)
```

Auto irrigation does not publish MQTT directly. When auto mode is enabled and irrigation is needed, the irrigation agent returns:

```python
decision.mqtt_command.topic
decision.mqtt_command.payload
```

The backend should publish that payload.

## Business-Side Agents

Main entry point:

```python
from business_agents import BusinessSupervisorAgent
```

Included:

- `InventoryAgent`
- `DemandMatchingAgent`
- `CropPlanningAdvisor`
- `BusinessSupervisorAgent`

The business agents keep scoring internal. Farmer-facing demand matching returns the top three buyer options.

## Combined Supervisor

Main entry point:

```python
from smart_farming_agents import SmartFarmingSupervisorAgent
```

Use this for dashboard/all-insights flows where the backend wants one combined response containing:

- agri review
- business review
- combined alerts
- next actions

Example:

```python
supervisor = SmartFarmingSupervisorAgent()
review = supervisor.full_review(
    agri_context=field_context,
    agri_weather=agri_weather,
    business_batches=inventory_batches,
    business_weather_by_crop=business_weather,
    buyer_demands=buyer_demands,
    crop_history=crop_history,
)
```

## Run Tests

From this folder:

```powershell
python -m unittest discover -s tests
```
