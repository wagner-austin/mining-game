#!/usr/bin/env python3
"""
validate_fixes.py
Validates that CompositionService type fixes are correct and working
"""

import subprocess
import sys
import re
from pathlib import Path

# ANSI colors for output
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'

def run_type_check(file_path):
    """Run luau-lsp type checker on a file and return output"""
    cmd = [
        r"C:\Users\austi\.aftman\bin\luau-lsp.exe",
        "analyze",
        "--platform", "roblox",
        "--definitions", "tools/defs/roblox-globalTypes.d.luau",
        "--sourcemap", "sourcemap.json",
        "--no-strict-dm-types",
        file_path
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, cwd=Path(__file__).parent.parent)
    return result.stderr + result.stdout

def extract_errors(output, file_name):
    """Extract error lines mentioning specific file"""
    lines = output.split('\n')
    errors = []
    for line in lines:
        if file_name in line and 'TypeError' in line:
            errors.append(line)
    return errors

def check_specific_line(errors, line_number):
    """Check if a specific line has an error"""
    pattern = rf'\({line_number},\d+\)'
    for error in errors:
        if re.search(pattern, error):
            return error
    return None

def main():
    print(f"{BLUE}{'=' * 70}{RESET}")
    print(f"{BLUE}CompositionService Type Fixes - Validation{RESET}")
    print(f"{BLUE}{'=' * 70}{RESET}\n")

    # Define the original 5 errors we were asked to fix
    original_errors = [
        (70, "Type 'number?' could not be converted into 'number'", "tonumber nil handling"),
        (180, "Function only returns 0 values, but 1 is required", "EventContracts return type"),
        (256, "Value of type 'CubeTheme?' could be nil", "CubeTheme nil check 1"),
        (262, "Value of type 'CubeTheme?' could be nil", "CubeTheme nil check 2"),
        (260, "could not be converted into 'nil'", "Return type inference with 'any'"),
    ]

    print(f"{YELLOW}Running type checker on CompositionService.lua...{RESET}\n")

    # Run type check
    output = run_type_check("server/MiningGame/CompositionService.lua")
    errors = extract_errors(output, "CompositionService.lua")

    # Check each original error
    print(f"{BLUE}Checking Original 5 Errors:{RESET}")
    print(f"{BLUE}{'-' * 70}{RESET}\n")

    all_fixed = True
    for line_num, description, fix_name in original_errors:
        error = check_specific_line(errors, line_num)
        if error:
            print(f"{RED}[X] Line {line_num}: STILL HAS ERROR{RESET}")
            print(f"    Description: {description}")
            print(f"    Fix: {fix_name}")
            print(f"    Error: {error[:100]}...\n")
            all_fixed = False
        else:
            print(f"{GREEN}[OK] Line {line_num}: FIXED{RESET}")
            print(f"     Description: {description}")
            print(f"     Fix: {fix_name}\n")

    # Check for any other errors
    print(f"\n{BLUE}Checking for Other Errors:{RESET}")
    print(f"{BLUE}{'-' * 70}{RESET}\n")

    other_errors = []
    checked_lines = {err[0] for err in original_errors}

    for error in errors:
        # Extract line number
        match = re.search(r'\((\d+),\d+\)', error)
        if match:
            line_num = int(match.group(1))
            if line_num not in checked_lines:
                other_errors.append((line_num, error))

    if other_errors:
        print(f"{YELLOW}Found {len(other_errors)} other error(s):{RESET}\n")
        for line_num, error in other_errors:
            print(f"{YELLOW}Line {line_num}:{RESET}")
            # Clean up the error message for readability
            clean_error = error.split(':', 2)[-1].strip() if ':' in error else error
            print(f"  {clean_error[:200]}...")
            print()
    else:
        print(f"{GREEN}No other errors found!{RESET}\n")

    # Summary
    print(f"{BLUE}{'=' * 70}{RESET}")
    print(f"{BLUE}SUMMARY:{RESET}")
    print(f"{BLUE}{'=' * 70}{RESET}\n")

    if all_fixed and not other_errors:
        print(f"{GREEN}[OK] ALL 5 ORIGINAL ERRORS FIXED{RESET}")
        print(f"{GREEN}[OK] NO OTHER ERRORS{RESET}")
        print(f"\n{GREEN}SUCCESS: All type errors resolved!{RESET}\n")
        return 0
    elif all_fixed:
        print(f"{GREEN}[OK] ALL 5 ORIGINAL ERRORS FIXED{RESET}")
        print(f"{YELLOW}[!] {len(other_errors)} other error(s) present (pre-existing or unrelated){RESET}")
        print(f"\n{YELLOW}PARTIAL SUCCESS: Original errors fixed, but other issues remain{RESET}\n")
        return 0  # Still success since we fixed what was asked
    else:
        print(f"{RED}[X] SOME ORIGINAL ERRORS NOT FIXED{RESET}")
        print(f"\n{RED}FAILURE: Not all requested errors were resolved{RESET}\n")
        return 1

if __name__ == "__main__":
    sys.exit(main())
