SHELL := bash
export PATH := $(HOME)/.aftman/bin:$(PATH)
# Simple dev helpers (requires selene, stylua, wally on PATH)

.PHONY: fmt lint wally-install test check run analyze help

fmt:
	stylua .

lint:
	selene --config .selene.toml .

wally-install:
	wally install

# Unit tests via Lune (no Studio required)
test:
	@echo "[TEST] Running specs via Lune"
	lune run scripts/run-tests.luau

# CI-style verification: format, lint, optional typecheck, and test reminder
check:
	@echo [1/4] Formatting with stylua
	- stylua .
	@echo "[2/4] Selene lint"
	- selene --config .selene.toml .
	@echo "[3/4] Luau analyze"
	python tools/luau_analyze_count.py .
	@echo "[4/4] Unit tests TestEZ"
	$(MAKE) --no-print-directory test

# Run the game via Rojo live sync
run:
	@echo "Starting Rojo serve (connect Studio Rojo plugin)"
	rojo serve

help:
	@echo "Targets: fmt, lint, wally-install, test"

# Run luau-lsp analyze and print a total error count at the end
analyze:
	@echo "Generating Rojo sourcemap (if rojo is available)"
	- bash -lc 'command -v rojo >/dev/null 2>&1 && rojo sourcemap default.project.json --output sourcemap.json || echo rojo not found; skipping sourcemap'
	- powershell -NoProfile -Command "if (Get-Command rojo -ErrorAction SilentlyContinue) { rojo sourcemap default.project.json --output sourcemap.json } else { Write-Host 'rojo not found; skipping sourcemap' }"
	@echo "Ensuring Roblox type definitions"
	- powershell -NoProfile -Command "if (-not (Test-Path tools\\defs)) { New-Item -ItemType Directory -Path tools\\defs -Force | Out-Null }; if (-not (Test-Path tools\\defs\\roblox-globalTypes.d.luau)) { try { Invoke-WebRequest https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau -UseBasicParsing -OutFile tools\\defs\\roblox-globalTypes.d.luau } catch { Write-Host 'warn: failed to download Roblox type definitions' } }"
	@echo "Analyzing (summary includes TOTAL ANALYZE ERRORS)"
	python tools/luau_analyze_count.py .

.PHONY: analyze-server
analyze-server:
	@echo "Analyzing server-only (TOTAL ANALYZE ERRORS at end)"
	python tools/luau_analyze_count.py server/MiningGame
