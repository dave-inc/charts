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
		echo "==> $$chart"; \
		helm lint "$$chart" || exit 1; \
	done
