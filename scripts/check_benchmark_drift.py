import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Final

ROOT_DIR: Final = Path(__file__).resolve().parent.parent
SHA256_PATTERN: Final = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True, slots=True)
class CanonicalError(Exception):
    detail: str

    def __str__(self) -> str:
        return self.detail


@dataclass(frozen=True, slots=True)
class BenchmarkTable:
    heading: str
    columns: tuple[str, ...]
    rows: tuple[tuple[str, ...], ...]


def require_mapping(value, field: str):
    if not isinstance(value, dict):
        raise CanonicalError(f"canonical field {field!r} must be an object")
    return value


def require_text(value, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise CanonicalError(f"canonical field {field!r} must be a non-empty string")
    return value


def require_cells(value, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        raise CanonicalError(f"canonical field {field!r} must be a non-empty array")
    cells = tuple(value)
    if not all(isinstance(cell, str) for cell in cells):
        raise CanonicalError(f"canonical field {field!r} must contain only strings")
    return cells


def parse_tables(value) -> tuple[BenchmarkTable, ...]:
    if not isinstance(value, list) or not value:
        raise CanonicalError("canonical field 'measured_tables' must be a non-empty array")

    tables = []
    for index, item in enumerate(value):
        table = require_mapping(item, f"measured_tables[{index}]")
        heading = require_text(table.get("heading"), f"measured_tables[{index}].heading")
        columns = require_cells(table.get("columns"), f"measured_tables[{index}].columns")
        raw_rows = table.get("rows")
        if not isinstance(raw_rows, list) or not raw_rows:
            raise CanonicalError(f"canonical table {heading!r} must have rows")
        rows = tuple(require_cells(row, f"{heading}.rows") for row in raw_rows)
        if not all(len(row) == len(columns) for row in rows):
            raise CanonicalError(f"canonical table {heading!r} has an inconsistent row width")
        tables.append(BenchmarkTable(heading, columns, rows))
    return tuple(tables)


def validate_replay_contract(value) -> None:
    contract = require_mapping(value, "replay_contract")
    hardware = require_mapping(contract.get("hardware"), "replay_contract.hardware")
    software = require_mapping(contract.get("software"), "replay_contract.software")
    prompts = require_mapping(contract.get("prompt_set"), "replay_contract.prompt_set")
    workloads = require_mapping(prompts.get("workloads"), "replay_contract.prompt_set.workloads")
    speculation = require_mapping(contract.get("speculation"), "replay_contract.speculation")
    cache = require_mapping(contract.get("cache_profile"), "replay_contract.cache_profile")
    model = require_mapping(contract.get("model"), "replay_contract.model")

    for field, item in (
        ("hardware.apu", hardware.get("apu")),
        ("software.mesa", software.get("mesa")),
        ("governor", contract.get("governor")),
        ("cache_profile.name", cache.get("name")),
        ("model.gguf", model.get("gguf")),
    ):
        require_text(item, f"replay_contract.{field}")

    missing_workloads = {"prose", "code", "json"} - workloads.keys()
    if missing_workloads:
        raise CanonicalError(f"canonical prompt set is missing: {', '.join(sorted(missing_workloads))}")
    if not isinstance(speculation.get("n_max"), int) or speculation["n_max"] < 1:
        raise CanonicalError("canonical n_max must be a positive integer")
    p_min = speculation.get("p_min")
    if not isinstance(p_min, int | float) or not 0 <= p_min <= 1:
        raise CanonicalError("canonical p_min must be between 0 and 1")
    sha256 = require_text(model.get("sha256"), "replay_contract.model.sha256")
    if SHA256_PATTERN.fullmatch(sha256) is None:
        raise CanonicalError("canonical GGUF sha256 must be 64 lowercase hexadecimal characters")


def read_canonical(path: Path) -> tuple[BenchmarkTable, ...]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    root = require_mapping(raw, "root")
    if root.get("schema_version") != 1:
        raise CanonicalError("canonical schema_version must be 1")
    validate_replay_contract(root.get("replay_contract"))
    return parse_tables(root.get("measured_tables"))


def read_markdown_table(readme: str, heading: str) -> tuple[tuple[str, ...], ...]:
    marker = f"### {heading}"
    if marker not in readme:
        raise CanonicalError(f"README is missing benchmark heading: {heading}")
    section = readme.split(marker, 1)[1]
    table_lines = []
    started = False
    for line in section.splitlines():
        if line.startswith("|"):
            started = True
            table_lines.append(line)
        elif started:
            break
    if len(table_lines) < 3:
        raise CanonicalError(f"README benchmark table is incomplete: {heading}")
    parsed = tuple(tuple(cell.strip() for cell in line.strip("|").split("|")) for line in table_lines)
    return (parsed[0], *parsed[2:])


def check_drift(canonical: Path, readme: Path) -> None:
    tables = read_canonical(canonical)
    readme_text = readme.read_text(encoding="utf-8")
    for table in tables:
        actual = read_markdown_table(readme_text, table.heading)
        expected = (table.columns, *table.rows)
        if actual != expected:
            raise CanonicalError(
                f"README table drifted from benchmarks/canonical.json: {table.heading}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description="Check README benchmark tables against canonical JSON")
    parser.add_argument("--canonical", type=Path, default=ROOT_DIR / "benchmarks" / "canonical.json")
    parser.add_argument("--readme", type=Path, default=ROOT_DIR / "README.md")
    args = parser.parse_args()
    try:
        check_drift(args.canonical, args.readme)
    except (CanonicalError, json.JSONDecodeError, OSError) as error:
        print(f"benchmark drift check failed: {error}", file=sys.stderr)
        return 1
    print("README benchmark tables match benchmarks/canonical.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
