#!/usr/bin/env python3
from collections import defaultdict
from pathlib import Path
import re
import sys


MEMORY_FACTORS = {
    "B": 1 / (1024 * 1024),
    "kB": 1000 / (1024 * 1024),
    "KB": 1000 / (1024 * 1024),
    "KiB": 1 / 1024,
    "MB": 1000 * 1000 / (1024 * 1024),
    "MiB": 1,
    "GB": 1000 * 1000 * 1000 / (1024 * 1024),
    "GiB": 1024,
}


def memory_to_mib(value: str) -> float:
    match = re.fullmatch(r"([0-9.]+)([A-Za-z]+)", value.strip())
    if not match:
        return 0.0
    number, unit = match.groups()
    return float(number) * MEMORY_FACTORS.get(unit, 0.0)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("uso: analyze_stats.py entrada.tsv saida.txt")

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    maxima = defaultdict(lambda: {"cpu": 0.0, "memory": 0.0, "memory_percent": 0.0})

    for raw_line in source.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("amostra"):
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            continue
        _, name, cpu, memory_usage, memory_percent = parts
        memory_current = memory_usage.split(" / ", 1)[0]
        values = maxima[name]
        values["cpu"] = max(values["cpu"], float(cpu.rstrip("%")))
        values["memory"] = max(values["memory"], memory_to_mib(memory_current))
        values["memory_percent"] = max(
            values["memory_percent"], float(memory_percent.rstrip("%"))
        )

    lines = ["CONTAINER\tCPU_MAX\tMEMORIA_MAX_MIB\tMEMORIA_MAX_PERCENTUAL"]
    for name in sorted(maxima):
        values = maxima[name]
        lines.append(
            f"{name}\t{values['cpu']:.2f}%\t{values['memory']:.2f} MiB\t"
            f"{values['memory_percent']:.2f}%"
        )

    destination.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

