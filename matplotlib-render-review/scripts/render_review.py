"""Render harness: execute a chart script and report the output PNG path."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

DEFAULT_OUTPUT = Path("/tmp/chart_review.png")


def parse_arguments() -> argparse.Namespace:
    """Parse CLI arguments for the render harness."""
    parser = argparse.ArgumentParser(
        description="Execute a matplotlib chart script and report the output PNG.",
    )
    parser.add_argument("script", type=Path, help="Path to the Python script to run")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"PNG output path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="Remove the rendered PNG after printing its path",
    )
    return parser.parse_args()


def run_script(script_path: Path, output_path: Path) -> subprocess.CompletedProcess[str]:
    """Execute the target script in the current Python environment."""
    return subprocess.run(
        [sys.executable, str(script_path)],
        env={**os.environ, "CHART_OUTPUT": str(output_path.resolve())},
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> None:
    """Render a chart script and print the output path on success."""
    arguments = parse_arguments()
    result = run_script(arguments.script, arguments.output)

    if result.returncode != 0:
        print(f"FAIL: script exited with code {result.returncode}", file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(1)

    output_resolved = arguments.output.resolve()

    if not output_resolved.exists():
        print(f"FAIL: expected output not found at {output_resolved}", file=sys.stderr)
        sys.exit(1)

    print(str(output_resolved))

    if arguments.cleanup:
        output_resolved.unlink()


if __name__ == "__main__":
    main()
