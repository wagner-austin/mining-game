#!/usr/bin/env python3
"""
Analyze all ItemService and module errors systematically
"""

import subprocess
import sys
from pathlib import Path
from collections import defaultdict

def main():
    print("=" * 70)
    print("ItemService Complete Error Analysis")
    print("=" * 70)
    print()

    # Run type checker
    cmd = [
        r"C:\Users\austi\.aftman\bin\luau-lsp.exe",
        "analyze",
        "--platform", "roblox",
        "--definitions", "tools/defs/roblox-globalTypes.d.luau",
        "--sourcemap", "sourcemap.json",
        "--no-strict-dm-types",
        "server/MiningGame/ItemService.lua",
        "server/MiningGame/ItemServiceModules/AutoCollector.lua",
        "server/MiningGame/ItemServiceModules/Collector.lua",
        "server/MiningGame/ItemServiceModules/DropRegistry.lua",
        "server/MiningGame/ItemServiceModules/Magnet.lua",
        "server/MiningGame/ItemServiceModules/Spawner.lua",
        "server/MiningGame/ItemServiceModules/Sweeper.lua",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, cwd=Path(__file__).parent.parent)
    output = result.stderr + result.stdout

    # Categorize errors by file and type
    errors_by_file = defaultdict(list)
    error_types = defaultdict(int)

    for line in output.split('\n'):
        if 'TypeError' in line or 'server/' in line or 'c:\\' in line:
            # Extract file name
            if 'ItemService.lua' in line:
                errors_by_file['ItemService'].append(line)
            elif 'AutoCollector' in line:
                errors_by_file['AutoCollector'].append(line)
            elif 'Collector' in line:
                errors_by_file['Collector'].append(line)
            elif 'DropRegistry' in line:
                errors_by_file['DropRegistry'].append(line)
            elif 'Magnet' in line:
                errors_by_file['Magnet'].append(line)
            elif 'Spawner' in line:
                errors_by_file['Spawner'].append(line)
            elif 'Sweeper' in line:
                errors_by_file['Sweeper'].append(line)

            # Count error types
            if 'Argument count mismatch' in line:
                error_types['Logger argument mismatch'] += 1
            elif 'Unknown type used in' in line:
                error_types['Missing type annotations'] += 1
            elif 'Key' in line and 'not found' in line:
                error_types['Missing config keys'] += 1
            elif 'could not be converted into' in line:
                error_types['Type conversion'] += 1
            elif 'different number of generic type parameters' in line:
                error_types['Generic type mismatch'] += 1

    # Print summary
    print("ERRORS BY FILE:")
    print("-" * 70)
    for file, errors in sorted(errors_by_file.items()):
        print(f"{file}: {len(errors)} errors")
    print()

    print("ERROR TYPES:")
    print("-" * 70)
    for err_type, count in sorted(error_types.items(), key=lambda x: -x[1]):
        print(f"{err_type}: {count}")
    print()

    print("=" * 70)
    print(f"TOTAL ERRORS: {sum(len(e) for e in errors_by_file.values())}")
    print("=" * 70)

    return 0

if __name__ == "__main__":
    sys.exit(main())
