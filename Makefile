.DEFAULT_GOAL := help
ROOT_APP := charts/root-app

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: template
template: ## Render the root app with the current values
	helm template root-app $(ROOT_APP) --namespace argocd

.PHONY: enabled
enabled: ## List the Applications that root-app will create
	@helm template root-app $(ROOT_APP) --namespace argocd \
		| awk '/^kind: Application$$/ {a=1} a && /^  name: / {print $$2; a=0}'

.PHONY: lint
lint: ## Lint the root app chart
	helm lint $(ROOT_APP)

.PHONY: test
test: ## Run all render tests in tests/
	@set -e; for t in tests/*.sh; do echo "== $$t"; bash $$t; done

.PHONY: bootstrap
bootstrap: ## Apply root-app to the cluster (needs Argo CD already running)
	kubectl apply -n argocd -f $(ROOT_APP)/templates/root-app.yaml
