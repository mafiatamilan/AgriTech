from __future__ import annotations

from datetime import date

from .models import InventoryBatch, InventoryStatus, WeatherSnapshot
from .shelf_life import ShelfLifeEngine


class InventoryAgent:
    def __init__(self, shelf_life_engine: ShelfLifeEngine | None = None) -> None:
        self.shelf_life_engine = shelf_life_engine or ShelfLifeEngine()

    def review_batch(
        self,
        batch: InventoryBatch,
        weather: WeatherSnapshot,
        today: date | None = None,
    ) -> InventoryStatus:
        shelf_life = self.shelf_life_engine.estimate(batch=batch, weather=weather, today=today)
        return InventoryStatus(
            batch_id=batch.batch_id,
            crop=batch.crop,
            quantity_kg=batch.quantity_kg,
            quality_grade=batch.quality_grade,
            harvest_date=batch.harvest_date,
            storage_type=batch.storage_type,
            shelf_life=shelf_life,
        )

    def review_inventory(
        self,
        batches: list[InventoryBatch],
        weather_by_crop: dict[str, WeatherSnapshot],
        today: date | None = None,
    ) -> tuple[InventoryStatus, ...]:
        statuses = []
        for batch in batches:
            weather = weather_by_crop.get(batch.crop.lower()) or weather_by_crop.get("default")
            if weather is None:
                raise ValueError(f"Missing weather snapshot for crop '{batch.crop}' or 'default'.")
            statuses.append(self.review_batch(batch=batch, weather=weather, today=today))

        return tuple(sorted(statuses, key=lambda item: item.shelf_life.remaining_shelf_life_days))
