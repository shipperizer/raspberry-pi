.PHONY=deps up istio-install

HELM3?=helm
SKAFFOLD?=skaffold
ISTIO_VERSION?=1.11.4
ISTIOCTL?=istio-$(ISTIO_VERSION)/bin/istioctl
TARGET_ARCH?=arm64

.EXPORT_ALL_VARIABLES:

deps:
	$(HELM3) repo add smallstep  https://smallstep.github.io/helm-charts
	$(HELM3) repo update

up:
	$(SKAFFOLD) run --profile smallstep-ca


apt:
	@echo "***install apt dependencies***"
	apt update
	apt install docker.io git build-essential python3-pip apt-transport-https ca-certificates curl

k8s-helpers: apt
	pip3 install httpie

k3s:
	curl -sfL https://get.k3s.io | sh -
	echo 'write-kubeconfig-mode: "0644"' | sudo tee /etc/rancher/k3s/config.yaml

istio-install:
	curl -L https://istio.io/downloadIstio | TARGET_ARCH=$(TARGET_ARCH) ISTIO_VERSION=$(ISTIO_VERSION) sh -
	$(ISTIOCTL) operator init --hub=docker.io/querycapistio
	@echo "***run twice as some CRD are not keen on being installed before all is setup***"
	$(ISTIOCTL) operator init --hub=docker.io/querycapistio
	@echo "***cert-manager required for the certificate to be deployed***"
	$(SKAFFOLD) run --profile=istio
	$(SKAFFOLD) run --profile=istio-config
	kubectl label namespace default istio-injection=enabled --overwrite