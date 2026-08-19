import asyncio
import os
import random
import termios
from dataclasses import dataclass

from app.core.config import get_settings


@dataclass
class UsbRelayResult:
    attempted: bool
    ok: bool
    action: str
    port: str
    error: str | None = None


def _baud_constant(baud_rate: int) -> int:
    baud = getattr(termios, f"B{baud_rate}", None)
    if baud is None:
        raise ValueError(f"Unsupported USB relay baud rate: {baud_rate}")
    return baud


def _write_serial_command(port: str, baud_rate: int, command: str) -> None:
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        attrs = termios.tcgetattr(fd)
        baud = _baud_constant(baud_rate)

        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = baud
        attrs[5] = baud
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 10

        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        os.write(fd, f"{command}\n".encode("ascii"))
        termios.tcdrain(fd)
    finally:
        os.close(fd)


async def dispatch_usb_relay(action: str) -> UsbRelayResult:
    settings = get_settings()
    normalized = action.lower()
    command = "ON" if normalized == "on" else "OFF" if normalized == "off" else None
    port = settings.USB_RELAY_PORT

    if command is None:
        return UsbRelayResult(
            attempted=False,
            ok=False,
            action=action,
            port=port,
            error="Unsupported relay action",
        )

    if not settings.USB_RELAY_ENABLED:
        return UsbRelayResult(attempted=False, ok=False, action=normalized, port=port)

    try:
        await asyncio.sleep(random.uniform(0.5, 1.0))
        await asyncio.to_thread(
            _write_serial_command,
            port,
            settings.USB_RELAY_BAUD_RATE,
            command,
        )
    except Exception as exc:
        return UsbRelayResult(
            attempted=True,
            ok=False,
            action=normalized,
            port=port,
            error=str(exc),
        )

    return UsbRelayResult(attempted=True, ok=True, action=normalized, port=port)
