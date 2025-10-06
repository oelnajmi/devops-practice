# ===== Config (override via: make KEY=value) =====
INFRA_DIR     ?= infra/terraform
CLUSTER_NAME  ?= devops-practice-cluster
REGION        ?= us-east-1

RELEASE       ?= devops-practice
NAMESPACE     ?= app
CHART         ?= ./charts/devops-practice
IMAGE_REPO    ?= ghcr.io/oelnajmi/devops-practice
TAG           ?= sha-$(shell git rev-parse --short HEAD)  # or "main"
PORT          ?= 3000

# ===== Targets =====
.PHONY: cluster-up app-up deploy status pods logs port-forward pf rollback app-down uninstall cluster-down print-tag

## Infra up (EKS + node)
cluster-up:
	@echo ">> Creating/Updating EKS cluster with Terraform in $(INFRA_DIR)"
	terraform -chdir=$(INFRA_DIR) init
	terraform -chdir=$(INFRA_DIR) apply -auto-approve
	@echo ">> Updating kubeconfig for '$(CLUSTER_NAME)' in '$(REGION)'"
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region $(REGION)
	@echo ">> Nodes:"
	kubectl get nodes

## App up (Helm install/upgrade)
app-up:
	@echo ">> Ensuring namespace '$(NAMESPACE)' exists"
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo ">> Deploying $(IMAGE_REPO):$(TAG) as '$(RELEASE)' in ns '$(NAMESPACE)'"
	helm upgrade --install $(RELEASE) $(CHART) -n $(NAMESPACE) \
		--set image.repository=$(IMAGE_REPO) \
		--set image.tag=$(TAG)
	@echo ">> Waiting for rollout..."
	kubectl rollout status deploy/$(RELEASE) -n $(NAMESPACE)

## Convenience alias: deploy == app-up (pass TAG=main or TAG=sha-xxxx)
deploy:
	$(MAKE) app-up TAG=$(TAG)

## Status & debugging helpers
status:
	kubectl rollout status deploy/$(RELEASE) -n $(NAMESPACE)

pods:
	kubectl get pods -n $(NAMESPACE) -o wide

logs:
	kubectl logs -f deploy/$(RELEASE) -n $(NAMESPACE)

rollback:
	kubectl rollout undo deploy/$(RELEASE) -n $(NAMESPACE)

## Port-forward to localhost
port-forward:
	@echo ">> Port-forward http://localhost:$(PORT) -> $(RELEASE):$(PORT) (Ctrl+C to stop)"
	kubectl port-forward -n $(NAMESPACE) deploy/$(RELEASE) $(PORT):$(PORT)

# Short alias
pf: port-forward

## Remove app
app-down:
	@echo ">> Uninstalling release '$(RELEASE)' from ns '$(NAMESPACE)'"
	-helm uninstall $(RELEASE) -n $(NAMESPACE)
	@echo ">> Deleting namespace (ignore if absent)"
	-kubectl delete ns $(NAMESPACE) --ignore-not-found=true

# Alias
uninstall: app-down

## Destroy cluster (tears down app first)
cluster-down:
	@echo ">> Ensuring app is removed before cluster destroy"
	-$(MAKE) app-down
	@echo ">> Destroying EKS via Terraform"
	terraform -chdir=$(INFRA_DIR) destroy -auto-approve

## Utility
print-tag:
	@echo $(TAG)
