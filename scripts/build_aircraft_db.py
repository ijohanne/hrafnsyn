#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from typing import Optional


def iter_records(root: Path):
    db_root = root / "public_html" / "db"
    type_lookup_path = db_root / "aircraft_types" / "icao_aircraft_types.json"

    with type_lookup_path.open() as handle:
        type_lookup = json.load(handle)

    for shard_path in sorted(db_root.glob("*.json")):
        prefix = shard_path.stem.upper()

        with shard_path.open() as handle:
            shard = json.load(handle)

        for suffix, record in shard.items():
            if suffix == "children" or not isinstance(record, dict):
                continue

            normalized = {"identity": f"{prefix}{suffix}".upper()}

            registration = normalize(record.get("r"))
            if registration is not None:
                normalized["registration"] = registration

            aircraft_type = normalize(record.get("t"))
            if aircraft_type is not None:
                normalized["aircraft_type"] = aircraft_type

                type_data = type_lookup.get(aircraft_type, {})
                if isinstance(type_data, dict):
                    type_description = normalize(type_data.get("desc"))
                    wake_turbulence = normalize(type_data.get("wtc"))

                    if type_description is not None:
                        normalized["type_description"] = type_description

                    if wake_turbulence is not None:
                        normalized["wake_turbulence_category"] = wake_turbulence

            type_description = normalize(record.get("desc"))
            if type_description is not None:
                normalized.setdefault("type_description", type_description)

            wake_turbulence = normalize(record.get("wtc"))
            if wake_turbulence is not None:
                normalized.setdefault("wake_turbulence_category", wake_turbulence)

            if len(normalized) > 1:
                yield normalized


def normalize(value):
    if isinstance(value, str):
        trimmed = value.strip().upper()
        if trimmed:
            return trimmed

    return None


def write_records(records, output_path: Path):
    output_path.parent.mkdir(parents=True, exist_ok=True)

    count = 0
    with output_path.open("w") as handle:
        for record in records:
            handle.write(json.dumps(record, separators=(",", ":")))
            handle.write("\n")
            count += 1

    return count


def write_metadata(output_path: Optional[Path], source_revision: Optional[str], count: int):
    if output_path is None:
        return

    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"record_count": count}

    if source_revision:
        payload["source_revision"] = source_revision

    with output_path.open("w") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Transform FlightAware dump1090 aircraft DB shards into Hrafnsyn NDJSON."
    )
    parser.add_argument("source_root", type=Path, help="Path to the dump1090 checkout root")
    parser.add_argument("output_path", type=Path, help="Output NDJSON path")
    parser.add_argument(
        "--metadata-output",
        type=Path,
        default=None,
        help="Optional metadata JSON output path",
    )
    parser.add_argument(
        "--source-revision",
        type=str,
        default=None,
        help="Optional upstream revision string to include in metadata",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    count = write_records(iter_records(args.source_root), args.output_path)
    write_metadata(args.metadata_output, args.source_revision, count)
    print(f"Wrote {count} aircraft records to {args.output_path}")


if __name__ == "__main__":
    main()
