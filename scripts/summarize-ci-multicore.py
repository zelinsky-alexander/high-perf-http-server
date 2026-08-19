#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
import statistics
from collections import defaultdict
from pathlib import Path

REQ_RE = re.compile(r"^Requests/sec:\s+([0-9.]+)\s*$", re.MULTILINE)
P99_RE = re.compile(r"^\s*99%\s+([0-9.]+)(us|ms|s)\s*$", re.MULTILINE)
ERR_RE = re.compile(r"Socket errors:\s+connect\s+(\d+),\s+read\s+(\d+),\s+write\s+(\d+),\s+timeout\s+(\d+)")
FILE_RE = re.compile(
    r"^(?P<name>.+)-measured-c(?P<connections>\d+)-r(?P<rep>\d+)-shard(?P<shard>\d+)\.txt$"
)


def latency_ms(value: str, unit: str) -> float:
    number = float(value)
    if unit == "us":
        return number / 1000.0
    if unit == "ms":
        return number
    if unit == "s":
        return number * 1000.0
    raise ValueError(f"unsupported latency unit: {unit}")


def parse_file(path: Path) -> tuple[float, float, int]:
    text = path.read_text(encoding="utf-8", errors="replace")
    req = REQ_RE.search(text)
    p99 = P99_RE.search(text)
    if not req or not p99:
        raise ValueError(f"could not parse wrk output: {path}")
    errors = 0
    match = ERR_RE.search(text)
    if match:
        errors = sum(int(value) for value in match.groups())
    return float(req.group(1)), latency_ms(p99.group(1), p99.group(2)), errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--markdown", required=True, type=Path)
    parser.add_argument("--csv", required=True, type=Path)
    parser.add_argument("--shards", required=True, type=int)
    args = parser.parse_args()

    per_rep: dict[tuple[str, int, int], list[tuple[float, float, int]]] = defaultdict(list)

    for path in sorted(args.input.glob("*-measured-c*-r*-shard*.txt")):
        match = FILE_RE.match(path.name)
        if not match:
            continue
        key = (
            match.group("name"),
            int(match.group("connections")),
            int(match.group("rep")),
        )
        per_rep[key].append(parse_file(path))

    if not per_rep:
        raise SystemExit("no multicore benchmark result files found")

    grouped: dict[tuple[str, int], list[tuple[float, float, int]]] = defaultdict(list)
    for (name, connections, _rep), samples in per_rep.items():
        if len(samples) != args.shards:
            raise ValueError(
                f"expected {args.shards} shard results for {name} c={connections}, got {len(samples)}"
            )
        aggregate_rps = sum(sample[0] for sample in samples)
        conservative_p99 = max(sample[1] for sample in samples)
        aggregate_errors = sum(sample[2] for sample in samples)
        grouped[(name, connections)].append((aggregate_rps, conservative_p99, aggregate_errors))

    rows: list[dict[str, object]] = []
    for (name, connections), samples in sorted(grouped.items(), key=lambda item: (item[0][1], item[0][0])):
        rps_values = [sample[0] for sample in samples]
        p99_values = [sample[1] for sample in samples]
        error_values = [sample[2] for sample in samples]
        rows.append(
            {
                "implementation": name,
                "connections": connections,
                "shards": args.shards,
                "repetitions": len(samples),
                "median_requests_per_sec": statistics.median(rps_values),
                "median_worst_shard_p99_ms": statistics.median(p99_values),
                "total_socket_errors": sum(error_values),
            }
        )

    fastest_by_connections: dict[int, float] = {}
    for row in rows:
        connections = int(row["connections"])
        throughput = float(row["median_requests_per_sec"])
        fastest_by_connections[connections] = max(fastest_by_connections.get(connections, 0.0), throughput)

    for row in rows:
        fastest = fastest_by_connections[int(row["connections"])]
        throughput = float(row["median_requests_per_sec"])
        row["vs_fastest_percent"] = throughput / fastest * 100.0 if fastest else 0.0

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    lines = [
        "# CI HTTP Benchmark Comparison — Multicore / Process-Sharded",
        "",
        f"Each implementation used {args.shards} single-executor server shards on the same GitHub-hosted runner. Client load was split evenly across shards and run concurrently. Throughput is summed across shards; p99 is the worst shard per repetition, then medianed across repetitions.",
        "",
        "| Connections | Implementation | Shards | Median aggregate req/s | Median worst-shard p99 | Socket errors | vs fastest |",
        "|---:|---|---:|---:|---:|---:|---:|",
    ]

    for row in rows:
        lines.append(
            "| {connections} | {implementation} | {shards} | {rps:,.2f} | {p99:.3f} ms | {errors} | {relative:.1f}% |".format(
                connections=row["connections"],
                implementation=row["implementation"],
                shards=row["shards"],
                rps=float(row["median_requests_per_sec"]),
                p99=float(row["median_worst_shard_p99_ms"]),
                errors=row["total_socket_errors"],
                relative=float(row["vs_fastest_percent"]),
            )
        )

    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- This category measures process-sharded multicore capacity, not native in-process scaling.",
            "- The same shard count is used for every implementation for fairness.",
            "- `vs fastest` is calculated separately for each connection level.",
            "- No absolute throughput threshold is enforced on GitHub-hosted runners.",
            "",
        ]
    )

    args.markdown.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
