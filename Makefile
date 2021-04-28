.PHONY=deps up

HELM3?=helm
SKAFFOLD?=skaffold

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
