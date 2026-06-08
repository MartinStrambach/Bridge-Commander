.DEFAULT_GOAL := help

SHELL := /bin/bash
SCRIPTS := scripts

.PHONY: help build-release notarize-app dmg notarize-dmg release clean check-tools

help:
	@echo "Targets:"
	@echo "  make check-tools    Verify signing identity, notary profile, and required CLIs"
	@echo "  make build-release  Archive + export a Developer ID signed .app"
	@echo "  make notarize-app   Submit the .app to Apple notary and staple"
	@echo "  make dmg            Wrap the stapled .app in a signed DMG"
	@echo "  make notarize-dmg   Submit the DMG to Apple notary and staple"
	@echo "  make release        Full pipeline (check-tools, build, notarize, dmg, notarize)"
	@echo "  make clean          Remove build/ and dist/"

check-tools:
	@bash $(SCRIPTS)/check-tools.sh

build-release:
	@bash $(SCRIPTS)/build-release.sh

notarize-app: build-release
	@bash $(SCRIPTS)/notarize-app.sh

dmg: notarize-app
	@bash $(SCRIPTS)/make-dmg.sh

notarize-dmg: dmg
	@bash $(SCRIPTS)/notarize-dmg.sh

release: check-tools notarize-dmg
	@echo "Release complete."

clean:
	@rm -rf build dist
	@echo "Removed build/ and dist/"
