"""Python loader for the proxy port range SoT defined in lib/netns-const.sh.

Single public API: ``load_port_range()`` returns ``(start, end)`` integers
that satisfy ``1 <= start <= end <= 65535`` (closed interval, matching the
iptables ``--dport START:END`` semantics applied by
``scripts/wsl2-netns-setup.sh``). All other helpers are private.

Resolution: ``__file__``-relative ``netns-const.sh`` in the same ``lib/``
directory. The loader does **not** consult any environment variable to
locate the SoT (cycle v0.4.1 / Unit 002 domain-model invariant I4 — no
runtime SoT override path). When installed via ``make install``, the file
ends up next to ``proxy.py`` automatically. Tests that need to inject a
fixture monkeypatch :func:`_resolve_netns_const_path` directly instead of
setting an environment variable.

Failure modes (all raise :class:`RuntimeError` with the resolved absolute
path included in the message):

- shell file not found
- ``sh`` subprocess exits non-zero / produces fewer than 2 stdout lines
  / produces non-numeric or leading-zero values
- ``START`` or ``END`` outside ``1..65535`` / ``START > END``

This Python validation mirrors the consumer-side validation in
``scripts/wsl2-netns-setup.sh`` so the contract documented in cycle
v0.4.1 / Unit 001 stays single-sourced. Shared test vectors live in
``tests/port_range_invalid_vectors.py``.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

__all__ = ["load_port_range"]


_PORT_MIN = 1
_PORT_MAX = 65535

# Inline shell script used to extract the two SoT values. Receives the
# netns-const.sh absolute path as $1 (positional, NOT string-interpolated)
# so any future change to the path representation cannot inject shell
# syntax (cycle v0.4.1 / Unit 002 code review R1 #1).
_EXTRACT_SCRIPT = (
    '. "$1" && '
    'printf "%s\\n%s" '
    '"$JAILRUN_PROXY_PORT_RANGE_START" '
    '"$JAILRUN_PROXY_PORT_RANGE_END"'
)


def _resolve_netns_const_path() -> Path:
    return Path(__file__).resolve().parent / "netns-const.sh"


def _read_raw_values(sot_path: Path) -> tuple[str, str]:
    if not sot_path.is_file():
        raise RuntimeError(f"netns-const.sh not found at {sot_path}")

    proc = subprocess.run(
        ["sh", "-c", _EXTRACT_SCRIPT, "netns_const_loader", str(sot_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "invalid JAILRUN_PROXY_PORT_RANGE: sh exited "
            f"{proc.returncode} ({proc.stderr.strip()}); "
            f"resolved netns-const.sh path: {sot_path}"
        )
    lines = proc.stdout.split("\n")
    if len(lines) < 2:
        raise RuntimeError(
            "invalid JAILRUN_PROXY_PORT_RANGE: subprocess returned "
            f"fewer than 2 lines (got {len(lines)}); "
            f"resolved netns-const.sh path: {sot_path}"
        )
    return lines[0], lines[1]


def _validate_int_str(raw: str, label: str, sot_path: Path) -> int:
    if raw == "":
        raise RuntimeError(
            f"invalid JAILRUN_PROXY_PORT_RANGE: {label} is empty; "
            f"resolved netns-const.sh path: {sot_path}"
        )
    if not raw.isdigit():
        raise RuntimeError(
            f"invalid JAILRUN_PROXY_PORT_RANGE: {label}={raw!r} is "
            f"not a decimal integer; resolved netns-const.sh path: {sot_path}"
        )
    # Leading-zero rejection mirrors setup.sh's case '0|0[0-9]*'.
    if len(raw) > 1 and raw[0] == "0":
        raise RuntimeError(
            f"invalid JAILRUN_PROXY_PORT_RANGE: {label}={raw!r} has a "
            f"leading zero; resolved netns-const.sh path: {sot_path}"
        )
    if raw == "0":
        raise RuntimeError(
            f"invalid JAILRUN_PROXY_PORT_RANGE: {label}=0 is below the "
            f"valid range [{_PORT_MIN}, {_PORT_MAX}]; "
            f"resolved netns-const.sh path: {sot_path}"
        )
    value = int(raw)
    if value < _PORT_MIN or value > _PORT_MAX:
        raise RuntimeError(
            f"invalid JAILRUN_PROXY_PORT_RANGE: {label}={value} is "
            f"outside [{_PORT_MIN}, {_PORT_MAX}]; "
            f"resolved netns-const.sh path: {sot_path}"
        )
    return value


def load_port_range() -> tuple[int, int]:
    """Return the proxy port range ``(START, END)`` from the shell SoT."""
    sot_path = _resolve_netns_const_path()
    raw_start, raw_end = _read_raw_values(sot_path)
    start = _validate_int_str(raw_start, "START", sot_path)
    end = _validate_int_str(raw_end, "END", sot_path)
    if start > end:
        raise RuntimeError(
            "invalid JAILRUN_PROXY_PORT_RANGE: "
            f"START={start} > END={end}; "
            f"resolved netns-const.sh path: {sot_path}"
        )
    return start, end
