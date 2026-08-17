from __future__ import annotations


DEFAULT_DISEASE_REMEDIES: dict[str, dict[str, tuple[str, ...] | str]] = {
    "tomato late blight": {
        "severity": "needs attention",
        "remedies": (
            "Remove infected leaves and dispose of them away from the field.",
            "Avoid overhead watering until symptoms reduce.",
            "Improve airflow around plants.",
            "Use locally approved fungicide if infection is spreading.",
        ),
        "prevention": (
            "Avoid wet foliage during humid periods.",
            "Rotate crops where possible.",
            "Inspect nearby tomato and potato plants.",
        ),
    },
    "tomato early blight": {
        "severity": "needs attention",
        "remedies": (
            "Remove lower infected leaves first.",
            "Mulch to reduce soil splash onto leaves.",
            "Use approved fungicide if lesions continue spreading.",
        ),
        "prevention": (
            "Avoid working plants when leaves are wet.",
            "Maintain spacing for airflow.",
        ),
    },
    "potato late blight": {
        "severity": "needs attention",
        "remedies": (
            "Remove infected foliage and monitor the field daily.",
            "Avoid irrigation that wets leaves.",
            "Use locally approved fungicide if conditions stay humid.",
        ),
        "prevention": (
            "Destroy volunteer potato plants.",
            "Avoid overhead irrigation in humid weather.",
        ),
    },
    "healthy": {
        "severity": "normal",
        "remedies": (
            "No disease action needed from this image.",
        ),
        "prevention": (
            "Continue regular inspection.",
            "Retake photos if new spots, yellowing, or wilting appears.",
        ),
    },
}


class DiseaseRemedyAdvisor:
    def __init__(self, remedies: dict[str, dict[str, tuple[str, ...] | str]] | None = None) -> None:
        self.remedies = remedies or DEFAULT_DISEASE_REMEDIES

    def lookup(self, crop: str, disease: str) -> dict[str, tuple[str, ...] | str]:
        key = "healthy" if disease == "healthy" else f"{crop} {disease}".strip().lower()
        return self.remedies.get(
            key,
            {
                "severity": "needs inspection",
                "remedies": (
                    "Isolate visibly affected plant parts if possible.",
                    "Retake a clearer image and inspect nearby plants.",
                    "Consult a local agriculture expert before applying chemicals.",
                ),
                "prevention": (
                    "Avoid spreading plant material between fields.",
                    "Monitor weather conditions that favor disease.",
                ),
            },
        )
