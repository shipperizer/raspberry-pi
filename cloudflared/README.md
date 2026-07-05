# Cloudflared Deployment on k0s

This folder contains Kustomize manifests to deploy `cloudflared` on a single-node `k0s` cluster. The primary goal of this architecture is to expose internal cluster resources to the public internet securely using a **Cloudflare Tunnel**, avoiding the need for inbound port forwarding on your home modem/router.

---

## 1. Architectural Design

Traditional setups require opening ports `80` and `443` on your home router and forwarding them directly to the node's host ports. This exposes your home IP to scanner traffic and vulnerability exploits.

By using Cloudflare Tunnels (`cloudflared`), the daemon inside the cluster initiates a secure **outbound** connection to Cloudflare's nearest edge server. Incoming internet traffic is routed through this persistent connection, allowing you to keep all inbound router ports completely closed.

### Visual Architecture Diagram

```mermaid
graph TD
    %% Define Styles
    classDef cf fill:#f6821f,stroke:#fff,stroke-width:2px,color:#fff;
    classDef k8s fill:#326ce5,stroke:#fff,stroke-width:2px,color:#fff;
    classDef client fill:#555,stroke:#fff,stroke-width:2px,color:#fff;
    classDef router fill:#88b04b,stroke:#fff,stroke-width:2px,color:#fff;

    %% Elements
    Client[Public Internet User]:::client
    CF[Cloudflare Edge / Proxy]:::cf
    
    subgraph LAN [Home Network - Behind NAT / Private IP]
        Router[Home Router / Modem <br/> <b>NO incoming ports open!</b>]:::router
        
        subgraph Cluster [k0s Single-Node Cluster]
            CFD[cloudflared Pod]:::k8s
            Cilium[Cilium Gateway Service <br/> <i>cilium-gateway-orbo-mate-gateway</i>]:::k8s
            OrboService[orbo-mate Service]:::k8s
        end
    end

    %% Connections
    Client -->|HTTPS:443| CF
    CFD -->|1. Establish Outbound Connection| Router
    Router -->|2. Secure Persistent Tunnel| CF
    CF <==>|3. Forward Incoming Requests| CFD
    CFD -->|4. Forward HTTP Traffic (Port 80)| Cilium
    Cilium -->|5. Route HTTPRoute| OrboService
```

### Key Advantages:
* **No Public IP Exposure**: Your ISP home gateway IP address is never revealed to clients; all clients interact with Cloudflare IPs.
* **No Router Configuration**: You don't need access to the modem/router admin dashboard to configure port forwarding or dynamic DNS.
* **Automatic TLS**: Cloudflare manages the SSL certificate on their edge network, taking care of HTTPS termination.
* **Security Controls**: You can layer Cloudflare Access policies, firewall rules, and DDoS protection on top of your public hostname.

---

## 2. Directory Structure

```
cloudflared/
├── README.md                 # Design and setup instructions
├── base/                     # Base resources
│   ├── kustomization.yaml
│   ├── deployment.yaml       # Deployment utilizing cloudflare/cloudflared:latest
│   ├── configmap.yaml        # Mountable configuration file (optional override)
│   └── secret.yaml           # Placeholder secret
└── overlays/
    └── production/           # Environment overlay
        ├── kustomization.yaml
        ├── secret.yaml       # Actual token (GIT-IGNORED)
        └── secret.yaml.example
```

---

## 3. Step-by-Step Setup Guide

### Step A: Configure Tunnel on Cloudflare Zero Trust
1. Log in to the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com).
2. Go to **Networks** -> **Tunnels** -> **Add a Tunnel**.
3. Select **Cloudflared** as the connector and click **Next**.
4. Name your tunnel (e.g. `pi-k0s-tunnel`) and click **Save tunnel**.
5. Under **Install and run a connector**, copy the long token string provided in the command line fields. It will look something like this:
   `eyJhIjoiNjE5...`

### Step B: Configure the Secret Locally
Do not commit your secret token to GitHub. We have configured [.gitignore](file:///home/alarm/shipperizer/raspberry-pi/.gitignore) to exclude `cloudflared/overlays/*/secret.yaml`.

1. Copy the example file:
   ```bash
   cp cloudflared/overlays/production/secret.yaml.example cloudflared/overlays/production/secret.yaml
   ```
2. Open the newly created `secret.yaml`:
   [cloudflared/overlays/production/secret.yaml](file:///home/alarm/shipperizer/raspberry-pi/cloudflared/overlays/production/secret.yaml)
3. Replace the placeholder token with your actual tunnel token:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: cloudflared-secret
   type: Opaque
   stringData:
     token: eyJhIjoiNjE5... # Your Cloudflare Token here
   ```

### Step C: Deploy to Cluster
Deploy the overlay manifests using the root `Makefile`:

```bash
make cloudflared-install
```

Or deploy directly using `kubectl`:

```bash
kubectl apply -k cloudflared/overlays/production
```

### Step D: Configure Routing on Cloudflare Dashboard
Now that the `cloudflared` pod is running and connected, configure the public hostnames to forward traffic inside your cluster.

1. In the **Tunnels** dashboard, click **Edit** on your running tunnel.
2. Go to the **Public Hostname** tab and click **Add a public hostname**.
3. Configure the mapping:
   * **Subdomain / Domain**: Your domain (e.g., `orbo-mate.yourdomain.com`).
   * **Service Type**: `HTTP`
   * **URL**: `cilium-gateway-orbo-mate-gateway.default.svc.cluster.local:80`
4. Under **Additional application settings** -> **HTTP Settings**:
   * **HTTP Host Header**: Set to your domain (e.g., `orbo-mate.yourdomain.com`). This ensures that your Cilium Gateway / HTTPRoute rule successfully matches the host header when processing requests!
5. Save the configuration.

---

## 4. Verification & Diagnostics

To check the logs and ensure the tunnel has successfully established a connection:

```bash
# Check Pod status
kubectl get pods -n default -l app=cloudflared

# View connection logs
kubectl logs -n default -l app=cloudflared
```

You should see logs showing `cloudflared` registering connections with Cloudflare edge locations:
```text
INF Connection 0495f4e6-d183-48b2-b1d8-a1b7ad7884ff registered connIndex=0 ip=198.41.200.193 location=ORD
INF Connection a3d1c0fa-2396-4074-be4b-7fe898be2c5a registered connIndex=1 ip=198.41.192.167 location=IAD
...
```
