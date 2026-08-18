"""Logging configuration for the backend.

Enables request/response + network (httpx) debug logging when DEBUG mode is on.
"""

import logging
import sys
from logging.handlers import RotatingFileHandler

from app.core.config import get_settings


def setup_logging() -> None:
    settings = get_settings()
    level = getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO)
    debug = settings.DEBUG or settings.LOG_LEVEL.upper() == "DEBUG"

    fmt = logging.Formatter(
        "%(asctime)s %(levelname)-8s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    root = logging.getLogger()
    root.setLevel(level)

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(fmt)
    root.addHandler(console)

    file_handler = RotatingFileHandler(
        "backend.log",
        maxBytes=5_000_000,
        backupCount=2,
    )
    file_handler.setFormatter(fmt)
    root.addHandler(file_handler)

    # Suppress noisy third-party loggers unless debugging network calls.
    # httpcore/hpack dump raw headers (including the Supabase apikey) at DEBUG,
    # so keep them at WARNING and only surface httpx's request/response summary.
    if debug:
        logging.getLogger("httpx").setLevel(logging.DEBUG)
        logging.getLogger("httpcore").setLevel(logging.WARNING)
        logging.getLogger("hpack").setLevel(logging.WARNING)
        logging.getLogger("urllib3").setLevel(logging.DEBUG)
    else:
        logging.getLogger("httpx").setLevel(logging.WARNING)
        logging.getLogger("httpcore").setLevel(logging.WARNING)
        logging.getLogger("hpack").setLevel(logging.WARNING)
        logging.getLogger("urllib3").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
