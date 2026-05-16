"""Shared invalid-value test vectors for the proxy port range SoT.

Single source of truth for the value-validation contract that both the
Python loader (``lib/netns_const_loader.py``) and the shell consumer
(``scripts/wsl2-netns-setup.sh``) must agree on. Both test suites import
or read from this file directly — there is no mirrored TSV / YAML, so a
divergence is impossible.

Each tuple is ``(start_raw, end_raw, reason_label)``.
"""

from __future__ import annotations

INVALID_VECTORS: list[tuple[str, str, str]] = [
    ("0001", "60099", "leading-zero-start"),
    ("60000", "0099", "leading-zero-end"),
    ("abc", "60099", "non-integer-start"),
    ("60000", "abc", "non-integer-end"),
    ("0", "60099", "below-min-start"),
    ("60000", "65536", "above-max-end"),
    ("60100", "60050", "reversed-range"),
    ("", "60099", "empty-start"),
    ("60000", "", "empty-end"),
]
