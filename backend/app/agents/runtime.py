"""Lazy loader for the standalone `agents/` package at the repo root.

Keeps numpy/Pillow and the agent modules out of router import time so the
API still boots when they are not installed. Callers use `agents()` once.
"""

import sys
from functools import lru_cache
from pathlib import Path

_REPO_AGENTS_DIR = Path(__file__).resolve().parents[3] / "agents"


@lru_cache(maxsize=1)
def agents() -> dict:
    if str(_REPO_AGENTS_DIR) not in sys.path:
        sys.path.insert(0, str(_REPO_AGENTS_DIR))
    import agri_agents
    import business_agents
    import smart_farming_agents

    return {
        "agri": agri_agents,
        "business": business_agents,
        "smart": smart_farming_agents,
    }