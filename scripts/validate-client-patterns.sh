#!/bin/bash
# CI validation script for client-side code patterns
# Run this in CI to prevent regressions

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'

echo "🔍 Validating client code patterns..."

# 1. Block client-side InvokeServer (except ClientRF itself)
echo "Checking for direct InvokeServer usage..."
if git grep -nE 'InvokeServer\(' -- \
  ':(glob)client/**/*.lua' \
  ':(exclude,glob)client/**/ClientRF.lua' \
  ':(exclude,glob)client/**/ResultClient.lua' \
  ':(exclude,glob)**/*.disabled'; then
    echo "❌ ERROR: Found direct InvokeServer calls in client code. Use ClientRF.call() instead."
    exit 1
fi

# 2. Block raw Remotes.RF in client
echo "Checking for raw Remotes.RF usage..."
if git grep -n 'Remotes\.RF\.' -- \
  ':(glob)client/**/*.lua' \
  ':(exclude,glob)client/**/ClientRF.lua' \
  ':(exclude,glob)**/*.disabled'; then
    echo "❌ ERROR: Found direct Remotes.RF access in client code. Use ClientRF.call() instead."
    exit 1
fi

# 3. Block math.max(0, ...) patterns (except physics calculations)
echo "Checking for math.max(0, ...) patterns..."
if git grep -nE 'math\.max\(0,' -- \
  ':(glob)**/*.lua' \
  ':(exclude,glob)**/*.disabled' \
  ':(exclude,glob)character/Movement/DoubleJump.client.lua'; then
    echo "❌ ERROR: Found math.max(0, ...) patterns. Use MathUtils.nonNegative() or MathUtils.saturatingSub() instead."
    exit 1
fi

# 4. Flag magic pixel values in UI tabs
echo "Checking for hardcoded pixel values in tabs..."
if git grep -nE 'UDim\.new\(\s*0\s*,\s*(4|6|8|10|12|16|20|22|24|28|30|32|36|40)\b' -- ':(glob)client/MiningGame/UI/Components/*Tab.lua'; then
    echo "⚠️  WARNING: Found hardcoded pixel values in UI tabs. Use UIConstants tokens instead."
fi

# 5. Check for new .disabled or .old files
echo "Checking for dead code files..."
if find . -name "*.disabled" -o -name "*.old.lua" | grep -v node_modules | head -1; then
    echo "⚠️  WARNING: Found .disabled or .old files. These should be deleted."
fi

# 6. Block direct GetProfile calls (except PlayerProfileGuard and tests)
echo "Checking for direct GetProfile calls..."
if git grep -nE 'ClientRF\.call\(["'\'']GetProfile["'\'']' -- \
  ':(glob)client/**/*.lua' \
  ':(glob)shared/**/*.lua' \
  ':(exclude,glob)**/PlayerProfileGuard.lua' \
  ':(exclude,glob)**/TestClient.client.lua' \
  ':(exclude,glob)**/*.disabled'; then
    echo "❌ ERROR: Found direct GetProfile calls. Use PlayerProfileGuard.get() instead."
    exit 1
fi

# 7. Check for TODO comments (informational)
echo "Checking for TODO comments..."
TODO_COUNT=$(git grep -c 'TODO:' -- '*.lua' 2>/dev/null | wc -l || echo 0)
if [ "$TODO_COUNT" -gt 0 ]; then
    echo "ℹ️  INFO: Found $TODO_COUNT files with TODO comments. Consider converting to GitHub issues."
fi

echo "✅ Client code validation complete!"