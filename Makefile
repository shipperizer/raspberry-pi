.PHONY: deps apt k8s-helpers k3s k0s-install test cilium-cli-install cilium-install istio-install loki cert-manager-install container-structure-test-install
 
 HELM3?=helm
 SKAFFOLD?=skaffold
 ISTIO_VERSION?=1.11.4
 CERT_MANAGER_VERSION?=v1.15.1
 CONTAINER_STRUCTURE_TEST_VERSION?=v1.22.1
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
CILIUM_OPTS?=--name $(CILIUM_NAME) --cluster-id $(CILIUM_ID) # --config host-reachable-services-protos=tcp --config enable-host-reachable-services=true --kube-proxy-replacement strict

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

k0s-install:
	curl -sSLf https://get.k0s.sh | sudo sh
	sudo mkdir -p /etc/k0s
	k0s config create | sudo tee /etc/k0s/k0s.yaml > /dev/null
	sudo python3 -c "import sys, re; \
		c = open('/etc/k0s/k0s.yaml').read(); \
		c = re.sub(r'telemetry:\s*\n\s*enabled:\s*true', 'telemetry:\n    enabled: false', c); \
		c = re.sub(r'provider:\s*\S+', 'provider: custom\n    kubeProxy:\n      disabled: true', c); \
		open('/etc/k0s/k0s.yaml', 'w').write(c)"
	sudo k0s install controller --single -c /etc/k0s/k0s.yaml
	sudo k0s start

k3s:
	curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=$(INSTALL_EXEC_COMMAND) sh -s -

test:
	echo INSTALL_K3S_EXEC=$(INSTALL_EXEC_COMMAND)

cilium-cli-install:
	curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-$(ARCH).tar.gz{,.sha256sum}
	sha256sum --check cilium-linux-$(ARCH).tar.gz.sha256sum
	sudo tar xzvfC cilium-linux-$(ARCH).tar.gz /usr/local/bin
	rm cilium-linux-$(ARCH).tar.gz{,.sha256sum}

cilium-install:
	$(KUBECTL) apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
	$(CILIUM) install $(CILIUM_OPTS) \
		--helm-set gatewayAPI.enabled=true \
		--helm-set gatewayAPI.hostNetwork.enabled=false \
		--helm-set gatewayAPI.service.type=NodePort \
		--helm-set ingressController.enabled=true \
		--helm-set ingressController.loadbalancerMode=shared \
		--helm-set ingressController.service.type=NodePort \
		--helm-set ingressController.service.insecureNodePort=30080 \
		--helm-set ingressController.service.secureNodePort=30443 \
		--wait

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

cert-manager-install:
	$(KUBECTL) apply -f https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml
	$(KUBECTL) wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager
	$(KUBECTL) apply -f cert-manager/cluster_issuer.yaml

container-structure-test-install:
	curl -LO https://github.com/GoogleContainerTools/container-structure-test/releases/download/$(CONTAINER_STRUCTURE_TEST_VERSION)/container-structure-test-linux-$(ARCH)
	chmod +x container-structure-test-linux-$(ARCH)
	sudo mv container-structure-test-linux-$(ARCH) /usr/local/bin/container-structure-test

