.DEFAULT_GOAL := help

SHELL := /bin/bash
SCRIPTS := scripts

.PHONY: help build test check bump build-release notarize-app dmg notarize-dmg release publish clean check-tools

help:
	@echo "Development:"
	@echo "  make build          Build the app (Debug); prints only errors, warnings and the result"
	@echo "  make test           Test packages changed since origin/main and their dependents"
	@echo "                      (PKG=all for every package, PKG=\"GitCore AppUI\" for some)"
	@echo "  make check          Package setup and docs checks, then build and test"
	@echo ""
	@echo "Release (RELEASE.md):"
	@echo "  make bump           Bump the patch version and commit (VERSION=x.y.z to choose)"
	@echo "  make check-tools    Verify signing identity, notary profile, and required CLIs"
	@echo "  make build-release  Archive + export a Developer ID signed .app"
	@echo "  make notarize-app   Submit the .app to Apple notary and staple"
	@echo "  make dmg            Wrap the stapled .app in a signed DMG"
	@echo "  make notarize-dmg   Submit the DMG to Apple notary and staple"
	@echo "  make release        Full pipeline (check-tools, build, notarize, dmg, notarize)"
	@echo "  make publish        Tag the commit and publish the DMG as a GitHub release"
	@echo "  make clean          Remove build/ and dist/"

build:
	@bash $(SCRIPTS)/build.sh

test:
	@bash $(SCRIPTS)/test.sh $(PKG)

# Runs every step even when one fails, so one run reports everything.
check:
	@status=0; \
	bash $(SCRIPTS)/check-packages.sh || status=1; \
	python3 $(SCRIPTS)/check-docs.py || status=1; \
	bash $(SCRIPTS)/build.sh || status=1; \
	bash $(SCRIPTS)/test.sh $(PKG) || status=1; \
	exit $$status

bump:
	@bash $(SCRIPTS)/bump-version.sh $(VERSION)

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

# Intentionally not dependent on `release` — publishing should not silently
# rebuild. The script verifies the DMG exists, is stapled, and is not stale.
publish:
	@bash $(SCRIPTS)/publish-github.sh

clean:
	@rm -rf build dist
	@echo "Removed build/ and dist/"
