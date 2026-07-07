#!/usr/bin/env python3
"""Merge per-agent OptimizationData/permutation_scores.csv into one agent Files CSV."""

from __future__ import annotations

import csv
import sys
from datetime import datetime
from pathlib import Path

HEADER = [
    "WeeklyFVG",
    "DailyFVG",
    "H4FVG",
    "M15FVG",
    "W1_HighLowZones",
    "D1_HighLowZones",
    "H4_HighLowZones",
    "M15_HighLowZones",
    "MinScore",
    "W1_BOS",
    "D1_BOS",
    "H4_BOS",
    "M15_BOS",
    "TopScoreCount",
    "ScoreP100",
    "ScoreP90",
]

PERM_KEY_COLS = HEADER[:13]


def permutation_key(row: dict[str, str]) -> tuple[str, ...]:
    return tuple(row.get(col, "").strip() for col in PERM_KEY_COLS)


def read_rows(csv_path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            return rows
        for raw in reader:
            if not raw:
                continue
            row = {col: (raw.get(col) or "").strip() for col in HEADER}
            if not any(row.values()):
                continue
            if not row["WeeklyFVG"] and not row["ScoreP100"]:
                continue
            rows.append(row)
    return rows


def find_source_csvs(tester_root: Path) -> list[Path]:
    patterns = [
        "Agent-*/MQL5/Files/OptimizationData/permutation_scores.csv",
        "Agent-*/MQL5/Files/OptimizationData/perm_*.csv",
        "Agent-*/MQL5/Files/optimization_permutation_summary.csv",
    ]
    sources: list[Path] = []
    seen: set[Path] = set()
    for pattern in patterns:
        for path in tester_root.glob(pattern):
            resolved = path.resolve()
            if resolved in seen or not resolved.is_file():
                continue
            seen.add(resolved)
            sources.append(resolved)
    return sorted(sources)


def choose_output_path(tester_root: Path) -> Path:
    agents = sorted(tester_root.glob("Agent-*/MQL5/Files"))
    if not agents:
        raise FileNotFoundError(f"No agent Files folders under {tester_root}")
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return agents[0] / f"optimization_permutation_summary_merged_{stamp}.csv"


def merge_rows(sources: list[Path]) -> tuple[list[dict[str, str]], list[str]]:
    merged: dict[tuple[str, ...], dict[str, str]] = {}
    source_notes: list[str] = []

    for source in sources:
        rows = read_rows(source)
        if not rows:
            continue
        source_notes.append(f"{source} ({len(rows)} row(s))")
        for row in rows:
            merged[permutation_key(row)] = row

    return list(merged.values()), source_notes


def write_output(output_path: Path, rows: list[dict[str, str]]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=HEADER)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    if len(sys.argv) > 1:
        tester_root = Path(sys.argv[1]).expanduser().resolve()
    else:
        tester_root = Path(
            r"C:\Users\sheer\AppData\Roaming\MetaQuotes\Tester"
            r"\D0E8209F77C8CF37AD8BF550E51FF075"
        )

    if not tester_root.exists():
        print(f"Tester root not found: {tester_root}", file=sys.stderr)
        return 1

    sources = find_source_csvs(tester_root)
    if not sources:
        print(f"No optimization score CSV files found under {tester_root}", file=sys.stderr)
        return 1

    rows, source_notes = merge_rows(sources)
    if not rows:
        print("No data rows found to merge.", file=sys.stderr)
        return 1

    output_path = choose_output_path(tester_root)
    write_output(output_path, rows)

    print(f"Merged {len(rows)} permutation row(s) from {len(sources)} file(s).")
    print(f"Output: {output_path}")
    for note in source_notes:
        print(f"  - {note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
