.PHONY=deps up istio-install

HELM3?=helm
SKAFFOLD?=skaffold
ISTIO_VERSION?=1.11.4
ISTIOCTL?=istio-$(ISTIO_VERSION)/bin/istioctl
KUBECTL?=kubectl
ARCH?=arm64
CILIUM?=cilium
CILIUM_ISTIOCTL?=./cilium-istioctl
HUBBLE?=hubble
POD_CIDR?=10.42.0.0/16
SERVICE_CIDR?=10.43.0.0/16
DNS_IP?=10.43.0.10
TLS_SAN?=
KUBE_PROXY?=
INSTALL_EXEC_COMMAND?="--disable traefik --flannel-backend none --write-kubeconfig-mode 0644 --cluster-cidr $(POD_CIDR) --service-cidr $(SERVICE_CIDR) --cluster-dns $(DNS_IP) --disable-network-policy $(TLS_SAN) $(KUBE_PROXY)"
CILIUM_NAME?=bomber
CILIUM_ID?=100
CILIUM_OPTS?=--cluster-name $(CILIUM_NAME) --cluster-id $(CILIUM_ID) --config host-reachable-services-protos=tcp --config enable-host-reachable-services=true --kube-proxy-replacement strict

.EXPORT_ALL_VARIABLES:

deps:
	$(HELM3) repo add cilium https://helm.cilium.io/
	$(HELM3) repo add smallstep  https://smallstep.github.io/helm-charts
	$(HELM3) repo add grafana https://grafana.github.io/helm-charts
	$(HELM3) repo update

apt:
	@echo "***install apt dependencies***"
	apt update
	apt install linux-modules-extra-raspi git build-essential python3 apt-transport-https ca-certificates

k8s-helpers: apt
	pip3 install httpie

k3s:
	curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=$(INSTALL_EXEC_COMMAND) sh -s -

test:
	echo INSTALL_K3S_EXEC=$(INSTALL_EXEC_COMMAND)

cilium-install:
	$(CILIUM) install $(CILIUM_OPTS) --wait
	echo "run the following"
	echo "$(KUBECTL) patch deployments.apps -n kube-system cilium-operator --patch \"$(cat cilium/operator.yaml)\""
	echo "$(KUBECTL) patch daemonset -n kube-system cilium --patch \"$(cat cilium/agent.yaml)\""
	echo "$(CILIUM) clustermesh enable --service-type LoadBalancer"
	echo "$(CILIUM) hubble enable --ui"

# cilium-istio:
# 	curl -L https://github.com/cilium/istio/releases/download/1.10.4/cilium-istioctl-1.10.4-$(ARCH).tar.gz | tar xz
# 	chmod +x $(CILIUM_ISTIOCTL)
# 	$(CILIUM_ISTIOCTL) operator init --hub=docker.io/querycapistio
# 	@echo "***run twice as some CRD are not keen on being installed before all is setup***"
# 	$(CILIUM_ISTIOCTL) operator init --hub=docker.io/querycapistio
# 	@echo "***cert-manager required for the certificate to be deployed***"
# 	$(SKAFFOLD) run --profile=istio
# 	$(SKAFFOLD) run --profile=istio-config
# 	kubectl label namespace default istio-injection=enabled --overwrite

istio-install:
	curl -L https://istio.io/downloadIstio | TARGET_ARCH=$(ARCH) ISTIO_VERSION=$(ISTIO_VERSION) sh -
	$(ISTIOCTL) operator init --hub=docker.io/querycapistio
	@echo "***run twice as some CRD are not keen on being installed before all is setup***"
	$(ISTIOCTL) operator init --hub=docker.io/querycapistio
	@echo "***cert-manager required for the certificate to be deployed***"
	$(SKAFFOLD) run --profile=istio
	$(SKAFFOLD) run --profile=istio-config
	kubectl label namespace default istio-injection=enabled --overwrite


loki:
	$(SKAFFOLD) run --profile loki
