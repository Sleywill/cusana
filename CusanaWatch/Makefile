# Cusana Watch — build, test and run.
#
# Build output goes to ~/Library/Developer/CusanaWatch, deliberately NOT into
# this folder: the repo lives in iCloud Drive, which stamps extended attributes
# onto build products and makes codesigning fail with
# "resource fork, Finder information, or similar detritus not allowed".

BUILD_ROOT := $(HOME)/Library/Developer/CusanaWatch
PROJECT    := CusanaWatch.xcodeproj
SCHEME     := CusanaWatch
SIM_NAME   := Cusana-41mm

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "  make test       Run the unit tests (macOS, fast, no simulator)"
	@echo "  make build      Build the watch app for the simulator"
	@echo "  make probe      Hit the live backend with the real Swift client"
	@echo "  make curl       Hit the live backend with plain curl"
	@echo "  make run        Boot a watch simulator and install the app"
	@echo "  make project    Regenerate the Xcode project from project.yml"
	@echo "  make verify     Everything: generate, test, build"
	@echo "  make secrets    Create Config/Secrets.xcconfig from the template"

.PHONY: project
project:
	xcodegen generate

.PHONY: test
test:
	cd CusanaKit && swift test --scratch-path $(BUILD_ROOT)/spm

.PHONY: build
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-sdk watchsimulator -destination 'generic/platform=watchOS Simulator' \
		-derivedDataPath $(BUILD_ROOT)/dd build

.PHONY: probe
probe:
	cd CusanaKit && swift run --scratch-path $(BUILD_ROOT)/spm cusana-probe

.PHONY: curl
curl:
	./scripts/probe.sh

.PHONY: run
run:
	./scripts/run-simulator.sh

.PHONY: verify
verify: project test build
	@echo "✓ project generated, tests green, watch app builds"

.PHONY: secrets
secrets:
	@test -f Config/Secrets.xcconfig \
		&& echo "Config/Secrets.xcconfig already exists — leaving it alone." \
		|| (cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig \
		    && echo "Created Config/Secrets.xcconfig — paste the JWT into it.")

.PHONY: clean
clean:
	rm -rf $(BUILD_ROOT)
