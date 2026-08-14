CHARTS := $(patsubst charts/%/Chart.yaml,%,$(wildcard charts/*/Chart.yaml))

.PHONY: help schemas lint

help:
	@echo "schemas  regenerate values.schema.json from each chart's schemas/"
	@echo "lint     helm lint every chart"

# values.schema.json is generated but committed, and CI fails if the committed
# copy is stale. Run this after editing anything under a chart's schemas/.
schemas:
	@for dir in charts/*/; do \
		[ -f "$$dir/schemas/schema.yaml" ] || continue; \
		echo "bundling $$dir"; \
		( cd "$$dir" && npx --yes @skriptfabrik/json-schema-bundler -d schemas/schema.yaml | jq . > values.schema.json ); \
	done

lint:
	@for dir in charts/*/; do \
		[ -f "$$dir/Chart.yaml" ] || continue; \
		helm dependency update "$$dir"; \
		helm lint "$$dir"; \
	done
