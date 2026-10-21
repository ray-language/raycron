# raycron — common tasks. `make` (or `make help`) lists them.

.DEFAULT_GOAL := help
.PHONY: help build test test-native fmt demo clean

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-12s %s\n", $$1, $$2}'

build: ## The native binary, ./raycron
	rm -f raycron
	ray build --native --release -o raycron src/main.ray

test: ## Tests on the VM (notifications headless)
	RAY_UI_BACKEND=headless ray test

test-native: ## The same tests as native binaries
	RAY_UI_BACKEND=headless ray test --native

fmt: ## Format the sources
	ray fmt -w src/*.ray tests/*.ray

demo: build ## The example configuration through Madrid's October night, from 02:58 CEST (Ctrl-C stops)
	cd examples && RAYCRON_CLOCK=2026-10-25T00:58:00Z ../raycron -c raycron.toml run

clean: ## Remove the binary and the example's state
	rm -f raycron examples/example.state* examples/heartbeat.log examples/backup.tgz
