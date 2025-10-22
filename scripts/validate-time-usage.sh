#!/bin/bash
# CI validation script to check for direct time function usage
# Run this in CI to ensure all time calls go through the Time module

echo "Checking for direct time function usage..."
echo "========================================="

# Define patterns to check
PATTERNS=(
    '\bos\.time\s*\('
    '\bos\.clock\s*\('
    '\btime\s*\('
    '\btick\s*\('
)

# Files to exclude from check
EXCLUDE_FILES="Time.lua|validate-time-usage.sh|migrate-to-time-module.lua"

# Track if any violations found
VIOLATIONS=0

for pattern in "${PATTERNS[@]}"; do
    echo ""
    echo "Checking for: $pattern"
    
    # Use ripgrep if available, otherwise fall back to grep
    if command -v rg &> /dev/null; then
        results=$(rg -n --glob '*.lua' --glob '!**/Time.lua' --glob '!**/scripts/**' --glob '!**/*.disabled' -e "$pattern" 2>/dev/null)
    else
        results=$(find . -name "*.lua" -not -path "*/Time.lua" -not -path "*/scripts/*" -not -name "*.disabled" -exec grep -Hn "$pattern" {} \; 2>/dev/null)
    fi
    
    if [ -n "$results" ]; then
        echo "❌ Found violations:"
        echo "$results"
        VIOLATIONS=$((VIOLATIONS + 1))
    else
        echo "✅ No violations found"
    fi
done

echo ""
echo "========================================="

if [ $VIOLATIONS -gt 0 ]; then
    echo "❌ FAILED: Found $VIOLATIONS pattern violations"
    echo "All time functions should use the Time module instead:"
    echo "  - Use Time.unix() instead of os.time() or time()"
    echo "  - Use Time.mono() instead of os.clock() or tick()"
    echo "  - For milliseconds, use Time.unixMs() or Time.monoMs()"
    exit 1
else
    echo "✅ PASSED: No direct time function usage found"
    exit 0
fi