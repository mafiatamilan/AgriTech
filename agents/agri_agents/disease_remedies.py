from __future__ import annotations


DEFAULT_DISEASE_REMEDIES: dict[str, dict[str, tuple[str, ...] | str]] = {
    # ── Corn ──────────────────────────────────────────────────────────
    "corn common rust": {
        "severity": "needs attention",
        "remedies": (
            "Remove heavily infected leaves to reduce spore spread.",
            "Apply a fungicide labelled for rust if lesions are spreading rapidly.",
            "Avoid overhead irrigation; water at the base of plants.",
        ),
        "prevention": (
            "Plant rust-resistant hybrids where available.",
            "Rotate crops — avoid corn in the same field two seasons in a row.",
            "Monitor during warm, humid weather.",
        ),
    },
    "corn gray leaf spot": {
        "severity": "needs attention",
        "remedies": (
            "Remove and destroy infected crop residue after harvest.",
            "Apply a recommended fungicide if lesions cover more than 5 % of leaf area.",
            "Improve airflow by widening row spacing in future plantings.",
        ),
        "prevention": (
            "Use certified disease-free seed.",
            "Rotate with non-host crops (soybean, sorghum).",
            "Avoid excessive nitrogen fertilisation.",
        ),
    },
    "corn leaf blight": {
        "severity": "needs attention",
        "remedies": (
            "Remove infected leaves early to slow spread.",
            "Apply fungicide if the disease is progressing quickly.",
            "Ensure good drainage around the field.",
        ),
        "prevention": (
            "Choose resistant varieties.",
            "Rotate crops annually.",
            "Till under crop debris after harvest.",
        ),
    },
    "corn healthy": {
        "severity": "normal",
        "remedies": (
            "No disease action needed.",
        ),
        "prevention": (
            "Continue regular scouting.",
            "Maintain balanced fertilisation and irrigation.",
        ),
    },
    # ── Potato ────────────────────────────────────────────────────────
    "potato early blight": {
        "severity": "needs attention",
        "remedies": (
            "Remove lower infected leaves first.",
            "Mulch to reduce soil splash onto leaves.",
            "Use approved fungicide if lesions continue spreading.",
        ),
        "prevention": (
            "Avoid working plants when leaves are wet.",
            "Maintain spacing for airflow.",
            "Rotate with non-solanaceous crops.",
        ),
    },
    "potato late blight": {
        "severity": "urgent",
        "remedies": (
            "Remove infected foliage and monitor the field daily.",
            "Avoid irrigation that wets leaves.",
            "Apply fungicide immediately if conditions stay humid.",
            "Destroy severely infected plants to protect the rest.",
        ),
        "prevention": (
            "Destroy volunteer potato plants.",
            "Use certified seed tubers.",
            "Avoid overhead irrigation in humid weather.",
        ),
    },
    "potato healthy": {
        "severity": "normal",
        "remedies": (
            "No disease action needed.",
        ),
        "prevention": (
            "Continue regular inspection.",
            "Monitor for Colorado potato beetle and late blight in wet seasons.",
        ),
    },
    # ── Rice ──────────────────────────────────────────────────────────
    "rice brown spot": {
        "severity": "needs attention",
        "remedies": (
            "Improve field drainage to reduce leaf wetness.",
            "Apply a balanced fertiliser — brown spot is common in nutrient-deficient soils.",
            "Remove heavily infected leaves.",
        ),
        "prevention": (
            "Use resistant rice varieties.",
            "Maintain proper soil fertility (especially potassium and silicon).",
            "Avoid dense planting; allow airflow between rows.",
        ),
    },
    "rice leaf blast": {
        "severity": "urgent",
        "remedies": (
            "Apply a blast-specific fungicide (e.g. tricyclazole or isoprothiolane) immediately.",
            "Drain standing water from the field temporarily.",
            "Remove and destroy infected leaf tips.",
        ),
        "prevention": (
            "Plant blast-resistant varieties.",
            "Avoid excessive nitrogen fertilisation.",
            "Maintain proper water management — alternate wetting and drying.",
            "Seed treatment with fungicide before planting.",
        ),
    },
    "rice healthy": {
        "severity": "normal",
        "remedies": (
            "No disease action needed.",
        ),
        "prevention": (
            "Continue regular field scouting.",
            "Maintain balanced water and nutrient management.",
        ),
    },
    # ── Wheat ─────────────────────────────────────────────────────────
    "wheat brown rust": {
        "severity": "needs attention",
        "remedies": (
            "Apply fungicide if pustules are spreading and heading stage is near.",
            "Remove volunteer wheat and grassy weeds near the field.",
            "Avoid late-season nitrogen which prolongs green tissue for the fungus.",
        ),
        "prevention": (
            "Sow rust-resistant varieties.",
            "Stagger planting dates to avoid peak rust season.",
            "Monitor fields weekly during warm, humid periods.",
        ),
    },
    "wheat yellow rust": {
        "severity": "needs attention",
        "remedies": (
            "Apply fungicide at first sign of yellow stripes on leaves.",
            "Remove infected leaf material where practical.",
            "Avoid overhead irrigation.",
        ),
        "prevention": (
            "Use certified resistant seed.",
            "Avoid early planting in high-risk regions.",
            "Keep the field free of grassy weeds that host the fungus.",
        ),
    },
    "wheat healthy": {
        "severity": "normal",
        "remedies": (
            "No disease action needed.",
        ),
        "prevention": (
            "Continue regular scouting.",
            "Maintain balanced fertilisation.",
        ),
    },
    # ── Generic healthy fallback ──────────────────────────────────────
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
