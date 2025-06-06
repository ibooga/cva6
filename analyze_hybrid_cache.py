#!/usr/bin/env python3
"""Analyze hybrid cache performance and generate reports."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Dict


from hybrid_cache.config import load_config
from hybrid_cache.runner import collect_stats
from hybrid_cache.visualization import (
    generate_comparison_chart,
    generate_timeline_view,
    generate_interactive_chart,
)
from hybrid_cache.parser import stream_vcd_signals

def write_report(results: Dict[str, Dict[str, Dict[str, int | float]]], tests: list[str], configs: list[str], out_dir: Path) -> None:
    report_md = out_dir / "cache_analysis_report.md"
    with report_md.open("w", encoding="utf-8") as fh:
        fh.write("# Hybrid Cache Analysis Report\n\n")
        fh.write("## Performance Summary\n\n")
        for test in tests:
            fh.write(f"### {test.replace('_', ' ').title()}\n\n")
            fh.write("| Configuration | Cycles | Hit Ratio (%) | Hits | Misses |\n")
            fh.write("|---------------|--------|--------------|------|--------|\n")
            for cfg in configs:
                stats = results.get(test, {}).get(cfg)
                if stats:
                    fh.write(
                        f"| {cfg} | {stats.get('cycles', 'N/A')} | {stats.get('hit_ratio', 0):.2f} | {stats.get('hits', 0)} | {stats.get('misses', 0)} |\n"
                    )
                else:
                    fh.write(f"| {cfg} | N/A | N/A | N/A | N/A |\n")
            fh.write("\n")
            if results.get(test):
                generate_comparison_chart(results[test], test, out_dir)
                fh.write(f"![{test} Hit Ratio](charts/{test}_hit_ratio.png)\n\n")
                fh.write(f"![{test} Cycles](charts/{test}_cycles.png)\n\n")
                hybrid_stats = results[test].get("WT_HYB")
                if hybrid_stats and hybrid_stats.get("mode_switches", 0) > 0:
                    fh.write("#### Hybrid Mode Analysis\n\n")
                    fh.write(f"- Mode Switches: {hybrid_stats.get('mode_switches', 0)}\n")
                    fh.write(f"- Set Associative Hits: {hybrid_stats.get('set_assoc_hits', 0)}\n")
                    fh.write(f"- Fully Associative Hits: {hybrid_stats.get('full_assoc_hits', 0)}\n")
                    fh.write(f"- Time in Set Associative Mode: {hybrid_stats.get('set_assoc_time', 0)} cycles\n")
                    fh.write(f"- Time in Fully Associative Mode: {hybrid_stats.get('full_assoc_time', 0)} cycles\n\n")
                    fh.write(f"![{test} Hybrid Hit Distribution](charts/{test}_hybrid_hit_distribution.png)\n\n")
            fh.write("---\n\n")
        fh.write("## Findings and Conclusions\n\n")
        fh.write("(Add analysis here.)\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze hybrid cache performance",
        epilog=(
            "Example:\n"
            "  python3 analyze_hybrid_cache.py results_dir --config config/hybrid_cache_analysis.yml\n"
            "  python3 analyze_hybrid_cache.py results_dir -o report -j 4 --verbose\n"
            "  python3 analyze_hybrid_cache.py results_dir --timeline-vcd path/to.vcd --signal hit"
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("comparison_dir", help="Directory containing comparison results")
    parser.add_argument("--config", help="YAML configuration file")
    parser.add_argument("--output", "-o", default="cache_analysis_report", help="Output directory")
    parser.add_argument(
        "--jobs",
        "-j",
        type=int,
        default=os.cpu_count(),
        help="Number of parallel workers (default: number of CPUs)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose output during parsing",
    )
    parser.add_argument(
        "--timeline-vcd",
        help="VCD file containing hit signal to plot",
    )
    parser.add_argument(
        "--signal",
        default="hit",
        help="Signal name to extract from VCD",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Generate interactive timeline HTML if plotly is available",
    )
    args = parser.parse_args()

    base = Path(args.comparison_dir)
    if not base.is_dir():
        raise SystemExit(f"{base} is not a directory")

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        cfg = load_config(args.config)
    except FileNotFoundError as e:
        parser.error(str(e))
    except Exception as e:
        parser.error(f"Failed to load configuration: {e}")

    results = collect_stats(
        cfg["tests"],
        cfg["configs"],
        base,
        jobs=args.jobs,
        verbose=args.verbose,
    )
    if args.timeline_vcd:
        values = list(stream_vcd_signals(args.timeline_vcd, args.signal))
        generate_timeline_view(values, args.signal, out_dir)
        if args.interactive:
            generate_interactive_chart(values, args.signal, out_dir)
    write_report(results, cfg["tests"], cfg["configs"], out_dir)
    print(f"Analysis report generated in {out_dir}")


if __name__ == "__main__":
    main()
