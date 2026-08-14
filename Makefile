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

# `|| exit 1` because a bare command in a for loop leaves make looking at the exit
# status of the loop, so a chart failing anywhere but last would pass silently.
lint:
	@for dir in charts/*/; do \
		[ -f "$$dir/Chart.yaml" ] || continue; \
		helm dependency update "$$dir" || exit 1; \
		helm lint "$$dir" || exit 1; \
	done
