CHARTS := $(patsubst charts/%/Chart.yaml,%,$(wildcard charts/*/Chart.yaml))

# Needed for `set -o pipefail` in the recipes below, which /bin/sh on Ubuntu is
# dash and does not support. Set here rather than via .SHELLFLAGS because that
# was added in make 3.82 and macOS still ships 3.81, where it is ignored without
# a word, so the protection would exist in CI and quietly not on anyone's laptop.
SHELL := /bin/bash

# Pinned so a new upstream release cannot change the generated output, or what
# runs inside the job that pushes it back to a branch, without a commit here.
BUNDLER := @skriptfabrik/json-schema-bundler@0.6.42

.PHONY: help schemas lint

help:
	@echo "schemas  regenerate values.schema.json from each chart's schemas/"
	@echo "lint     helm lint every chart"

# values.schema.json is generated but committed, and CI fails if the committed
# copy is stale. Run this after editing anything under a chart's schemas/.
# Written to a temp file and moved into place only on success. A redirect straight
# onto values.schema.json truncates it before the bundler runs, so a failure would
# leave an empty schema that helm cannot parse. pipefail is what makes that failure
# visible at all, since jq alone would report success on empty input.
schemas:
	@for dir in charts/*/; do \
		[ -f "$$dir/schemas/schema.yaml" ] || continue; \
		echo "bundling $$dir"; \
		( set -o pipefail; cd "$$dir" && npx --yes $(BUNDLER) -d schemas/schema.yaml | jq . > values.schema.json.tmp && mv values.schema.json.tmp values.schema.json ) \
			|| { rm -f "$$dir/values.schema.json.tmp"; echo "failed to bundle $$dir" >&2; exit 1; }; \
	done

.PHONY: test lint

# Runs helm-unittest for every chart that has a tests/ directory, so this
# doesn't need updating as more charts gain test coverage.
test:
	@for d in charts/*/tests; do \
		chart=$$(dirname "$$d"); \
		echo "==> $$chart"; \
		helm unittest "$$chart" || exit 1; \
	done

# Runs helm lint for every chart, so this doesn't need updating as more
# charts are added.
lint:
	@for d in charts/*/Chart.yaml; do \
		chart=$$(dirname "$$d"); \
    [ -f "$$d/Chart.yaml" ] || continue; \
		echo "==> $$chart"; \
    helm dependency update "$$d" || exit 1; \
		helm lint "$$chart" || exit 1; \
	done
