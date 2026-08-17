from __future__ import annotations

import json
from pathlib import Path
from typing import Any


PDDD_NORMALIZATION_MEAN: tuple[float, float, float] = (0.416, 0.468, 0.355)
PDDD_NORMALIZATION_STD: tuple[float, float, float] = (0.210, 0.206, 0.213)


def load_pddd_labels(labels_path: str) -> tuple[str, ...]:
    """Load PDDD labels from class_indices.json or a one-label-per-line file.

    PDDD's model output order must match the downloaded class index mapping. Do
    not guess this order from crop names.
    """

    path = Path(labels_path)
    if not path.exists():
        raise FileNotFoundError(f"PDDD labels file not found: {labels_path}")

    if path.suffix.lower() == ".json":
        return _labels_from_json(json.loads(path.read_text(encoding="utf-8")))

    labels = tuple(line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
    if not labels:
        raise ValueError(f"No labels found in {labels_path}.")
    return labels


def _labels_from_json(data: Any) -> tuple[str, ...]:
    if not isinstance(data, dict) or not data:
        raise ValueError("PDDD class index JSON must be a non-empty object.")

    pairs: list[tuple[int, str]] = []
    for key, value in data.items():
        if isinstance(value, int):
            pairs.append((value, str(key)))
            continue
        if isinstance(key, str) and key.isdigit():
            pairs.append((int(key), str(value)))
            continue
        raise ValueError("Unsupported PDDD class index format.")

    pairs.sort(key=lambda item: item[0])
    expected = list(range(len(pairs)))
    actual = [index for index, _ in pairs]
    if actual != expected:
        raise ValueError("PDDD class indices must be contiguous and start at 0.")
    return tuple(label for _, label in pairs)
