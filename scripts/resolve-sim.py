#!/usr/bin/env python3
"""Resolve the UDID of the newest available iOS Simulator matching a given
device name and iOS major version. Prints the UDID on stdout.

Usage: scripts/resolve-sim.py "iPhone 17 Pro" 26

CI uses this so xcodebuild destinations are not pinned to specific patch
versions. xcodebuild's `OS=` matcher requires an exact match (e.g. `26.4`
will not match an installed `26.4.1` runtime), which causes the pipeline
to break every time Apple ships a point release. Resolving by major
version keeps the build green across patch updates.
"""
import json
import re
import subprocess
import sys


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.stderr.write(f"usage: {argv[0]} <device-name> <ios-major>\n")
        return 2
    name, major = argv[1], argv[2]

    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        check=True, capture_output=True, text=True,
    ).stdout
    data = json.loads(raw)

    # Runtime keys look like:
    #   com.apple.CoreSimulator.SimRuntime.iOS-26-4-1
    #   com.apple.CoreSimulator.SimRuntime.iOS-18-6
    # The groups after the major are minor and patch.
    rt_re = re.compile(r"iOS-(\d+)(?:-(\d+))?(?:-(\d+))?")
    candidates: list[tuple[tuple[int, int, int], str]] = []
    for runtime, devices in data["devices"].items():
        m = rt_re.search(runtime)
        if not m or m.group(1) != major:
            continue
        version = tuple(int(g) if g else 0 for g in m.groups())
        for d in devices:
            if d.get("isAvailable") and d["name"] == name:
                candidates.append((version, d["udid"]))

    if not candidates:
        sys.stderr.write(
            f"No available iOS Simulator matching name={name!r} ios={major}.x\n"
        )
        return 1

    candidates.sort(reverse=True)
    print(candidates[0][1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
