# Simple dev helpers (requires selene, stylua, wally on PATH)

.PHONY: fmt lint wally-install test check run help

fmt:
	stylua .

lint:
	selene .

wally-install:
	wally install

# Test execution happens in Studio via the disabled server script
test:
	@echo "Tests run in Studio:"
	@echo " - Run 'wally install' to fetch TestEZ"
	@echo " - Start Rojo (serve or build)"
	@echo " - Enable 'ServerScriptService/TestRunner.server.lua' in Studio to execute specs"

# CI-style verification: format check, non-blocking lint, optional typecheck, and test reminder
check:
	@echo "[1/4] Stylua format check" && stylua --check .
	@echo "[2/4] Selene lint (non-blocking)" && -selene . || true
	@echo "[3/4] Luau analyze (if installed; non-blocking)" && -luau-analyze . || true
	@echo "[4/4] Tests via Studio runner (see 'make test')"
	@echo "    Tip: enable ServerScriptService/TestRunner.server.lua in Studio"

# Run the game via Rojo live sync
run:
	@echo "Starting Rojo serve (connect Studio Rojo plugin)"
	rojo serve

help:
	@echo "Targets: fmt, lint, wally-install, test"
