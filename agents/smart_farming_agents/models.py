from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from agri_agents.models import AgriReview
from business_agents.models import BusinessReview


@dataclass(frozen=True)
class SmartFarmingReview:
    agri_review: Optional[AgriReview] = None
    business_review: Optional[BusinessReview] = None
    alerts: tuple[str, ...] = field(default_factory=tuple)
    next_actions: tuple[str, ...] = field(default_factory=tuple)
