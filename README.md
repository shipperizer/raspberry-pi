# Raspberry Pi 4B Single-Node Setup: k0s, Cilium, Gateway API & cert-manager

This repository provides manifests and a [Makefile](file:///home/alarm/shipperizer/raspberry-pi/Makefile) to configure and deploy a single-node Kubernetes cluster on a Raspberry Pi 4B (arm64) using **k0s** and **Cilium** with the modern **Gateway API**.

---

## Architecture Overview

```
                      +-----------------------------+
                      |         Home Router         |
                      |  Exposes ports 80 & 443     |
                      +--------------+--------------+
                                     |
                         Port 80     |     Port 443
                     (HTTP Challenge)|  (Secure Traffic)
                                     v
                      +--------------+--------------+
                      |      Raspberry Pi Node      |
                      |  (Envoy Gateway on Host Net)|
                      |   HTTP: 80, HTTPS: 443      |
                      +--------------+--------------+
                                     |
                                     | (Gateway API / Routing)
                                     v
                     +---------------+---------------+
                     |                               |
                     v                               v
            +--------+-------+             +---------+-------+
            |   deathstar    |             |     xwing       |
            | (Service: Port |             | (Service: Port  |
            |      80)       |             |      80)        |
            +----------------+             +-----------------+
```

---

## 1. Prerequisites & System Preparation

1. Install **Ubuntu Server 64-bit (aarch64)** on your Raspberry Pi 4B.
2. Install necessary kernel modules and tools:
   ```bash
   make apt
   ```
   This installs `linux-modules-extra-raspi` (mandatory for Cilium eBPF functionalities on Raspberry Pi kernels), `git`, `build-essential`, and `python3`.

3. Ensure systemd-sysctl uses the correct rp_filter settings if running on latest Arch/Ubuntu distributions:
   ```bash
   echo 'net.ipv4.conf.lxc*.rp_filter = 0' | sudo tee /etc/sysctl.d/99-override_cilium_rp_filter.conf
   sudo systemctl restart systemd-sysctl
   ```

4. Install `container-structure-test` (ARM64 binary) to verify container structures during testing:
   ```bash
   make container-structure-test-install
   ```

---

## 2. Bootstrapping k0s Single-Node Cluster

We boot a single-node k0s cluster configured to allow a custom CNI and optimized for a low memory footprint (ideal for a Raspberry Pi 4B).

### Memory Optimization & Configuration
* **No Telemetry**: Disabled to save CPU and bandwidth.
* **No kube-proxy**: Disabled completely to allow Cilium to run in `kube-proxy-replacement` mode, saving significant memory.
* **Custom Network Provider**: Set to `custom` in [k0s.yaml](file:///etc/k0s/k0s.yaml) to prevent the installation of default CNI plugins (e.g. Kube-Router or Calico), preparing the cluster for Cilium.

Run the installer target:
```bash
make k0s-install
```

### Accessing the Cluster
Extract the administrative kubeconfig:
```bash
mkdir -p ~/.kube
sudo k0s kubeconfig admin | tee ~/.kube/config > /dev/null
chmod 600 ~/.kube/config
```

---

## 3. Installing Cilium CLI and CNI

### Step A: Install Cilium CLI
Download and install the latest ARM64 binary:
```bash
make cilium-cli-install
```

### Step B: Deploy Cilium
Deploy Cilium with Gateway API, L2 Announcements, and Hubble observability enabled. The deployment uses the helm configuration file `cilium/values.yaml`:
```bash
make cilium-install
```

This target:
1. Applies the **Gateway API CRDs**.
2. Deploys Cilium using the configuration file [cilium/values.yaml](file:///home/alarm/shipperizer/raspberry-pi/cilium/values.yaml), which configures:
   * `cluster.name: bomber`: Configures the cluster name.
   * `kubeProxyReplacement: true`: Enables eBPF-based kube-proxy replacement, which is required for Gateway API.
   * `operator.replicas: 1`: Sets replicas to 1 (ideal for single-node setups).
   * `routingMode: tunnel` & `tunnelProtocol: vxlan`: Uses VXLAN tunneling for network routing.
   * `ingressController.enabled: false`: Disables default Cilium Ingress Controller.
   * `l7Proxy: true`: Enables the L7 proxy.
   * `l2announcements.enabled: true`: Enables L2 announcements.
   * `gatewayAPI.enabled: true`: Enables support for Gateway API resources.
   * `gatewayAPI.hostNetwork.enabled: true`: Enables host networking for the Gateway proxy (Envoy binds directly to host ports `80` and `443` on the Raspberry Pi node).
   * `k8sServiceHost: 192.168.86.27` & `k8sServicePort: 6443`: Explicitly points to the Kubernetes API server host.
   * `hubble`: Enables Hubble, Hubble Relay, and Hubble UI for observability.
3. Applies `cilium/l2-announcements.yaml` to define the LoadBalancer IP pool (`192.168.86.30-192.168.86.35`) and the L2 Announcement Policy.
4. Applies `cilium/certificate.yaml` to request the Let's Encrypt production SSL certificate for the domain.

---

## 4. Cert-Manager Setup & ACME HTTP-01 Challenges

### Installing cert-manager
Install cert-manager and wait for its webhook service to start:
```bash
make cert-manager-install
```

This applies the [cluster_issuer.yaml](file:///home/alarm/shipperizer/raspberry-pi/cert-manager/cluster_issuer.yaml) which defines staging and production Let's Encrypt `ClusterIssuers` configured to use the Gateway HTTPRoute solver:
```yaml
solvers:
- http01:
    gatewayHTTPRoute:
      parentRefs:
      - name: orbo-mate-gateway
        namespace: default
```

### Reliable Port-Forwarding Strategy
Because your Raspberry Pi is hosted inside a private home network behind a NAT router:
1. Let's Encrypt requires port `80` to be reachable from the internet for the `HTTP-01` challenge validation.
2. Setup **Port Forwarding** on your home internet router:
   * Forward incoming WAN port **80** to the Raspberry Pi node's IP on LAN port **80**.
   * Forward incoming WAN port **443** to the Raspberry Pi node's IP on LAN port **443**.
3. Since Cilium is configured with `gatewayAPI.hostNetwork.enabled: true`, Envoy binds directly to host ports `80` and `443` on the Raspberry Pi node, handling the HTTP-01 challenge and secure traffic directly on those ports.

---

## 5. Gateway and HTTPRoute Deployment

Once Cilium and cert-manager are running, apply the Gateway and HTTPRoute manifests:

### A. Deploy the Gateway
Apply [gateway.yaml](file:///home/alarm/shipperizer/raspberry-pi/cilium/gateway.yaml):
```bash
kubectl apply -f cilium/gateway.yaml
```
This deploys a `Gateway` utilizing `gatewayClassName: cilium` that listens on port `80` (HTTP) and port `443` (HTTPS with TLS termination pointing to secret `cilium-gateway-tls`).

### B. Deploy HTTPRoutes
Apply [httproutes.yaml](file:///home/alarm/shipperizer/raspberry-pi/cilium/httproutes.yaml):
```bash
kubectl apply -f cilium/httproutes.yaml
```
This routes paths:
* `/deathstar` to the `deathstar` service.
* `/xwing` to the `xwing` service.

---

## 6. ArgoCD

* Create a secret for `image-updater` builds (matching default namespace pull credentials):
  ```bash
  echo '{"auths":{"ghcr.io":{"auth":"*****************"}}}' | kubectl create secret generic regcred-github --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin -n argocd
  ```
* Port-forward the service locally and follow the ArgoCD getting started guide.
* Setup SSH Git credentials for image-updater:
  ```bash
  kubectl -n argocd create secret generic git-creds --from-file=sshPrivateKey=<path/to/id_rsa>
  ```
* Register SSH repository links:
  ```bash
  argocd repo add git@github.com:shipperizer/furry-train.git --ssh-private-key-path ~/.ssh/bomber_id_ed25519 --name furry-train
  argocd repo add git@github.com:shipperizer/fluffy-octo-telegram.git --ssh-private-key-path ~/.ssh/bomber_id_ed25519 --name fluffy-octo-telegram   
  ```

---

## 7. Kaniko

Create an opaque secret for container registry credentials:
```bash
echo '{"auths":{"ghcr.io":{"auth":"****************"}}}' | kubectl create secret generic regcred-github-kaniko --from-file=config.json=/dev/stdin
```

---

## 8. Contour Ingress (Alternative)

If you prefer Contour:
1. Disable Traefik/Cilium ingress.
2. Deploy Contour via Skaffold:
   ```bash
   skaffold run --profile contour
   ```
3. Expose the Envoy service port on your router.
