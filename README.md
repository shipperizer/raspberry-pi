# RaspberryPI setup

* install `Ubuntu Server 64bit` via `raspberryPi Imager`
* check Makefile `apt` target to install dependencies
* run `k3s` target to install K3s
** restart `k3s.service` and export `kubeconfig`
* add various `imagePullSecrets` secrets in `k8s`

```
ubectl create secret docker-registry regcred-github --docker-server=https://ghcr.io/ --docker-username=shipperizer --docker-password=<GH_PAT> --docker-email=alexcabb@gmail.com
```

* if using `make k3s` cilium will need to be installed before things work properly
* if wanted to use a public dns, add `--tls-san <dns record>` to have it added to the tls certificate


## Cilium

Follow the steps in [here](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/)

to install `cilium CLI` and `hubble CLI`

```
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-arm64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-arm64.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-arm64.tar.gz /usr/local/bin
rm cilium-linux-arm64.tar.gz{,.sha256sum}
export HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-arm64.tar.gz{,.sha256sum}
sha256sum --check hubble-linux-arm64.tar.gz.sha256sum
sudo tar xzvfC hubble-linux-arm64.tar.gz /usr/local/bin
rm hubble-linux-arm64.tar.gz{,.sha256sum}
```

to install in the cluster look at the `Makefile` target `cilium`


## Istio

Here we have 2 options:
* run `make istio-install` to get istio running via istio-operator, cni-plugin will be installed as well
* use cilium customized istio (experimental)
```
curl -L https://github.com/cilium/istio/releases/download/1.10.4/cilium-istioctl-1.10.4-linux-arm64.tar.gz | tar xz
```

** an ingress class resource will be created so that is easier to generate certs via cert-manager with the `istio` ingress class 

** for the cm-acme-solver to work, its service port will have to be exposed via the router for the certificate challenge to be accepted, once done revert to open the gateway port 80 

## Cert-Manager

* Install cert-manager via `kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml`


example of a cluster issuer:

```
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: http-issuer
spec:
  acme:
    email: <username>
    server: https://acme-v02.api.letsencrypt.org/directory
    preferredChain: "ISRG Root X1"
    privateKeySecretRef:
      name: http-issuer-account-key
    solvers:
    - http01:
       ingress:
         class: istio
```


## ArgoCD

* create a secret for `image-updater` builds, same as the one needed to pull images (which is in the default namespace):
```
echo '{"auths":{"ghcr.io":{"auth":"*****************"}}}' | kubectl create secret generic regcred-github --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin -n argocd
```
* port forward the service locally and follow the `Getting Started` guide [here](https://argoproj.github.io/argo-cd/getting_started/)


* add ssh git creds for image-updater so that it can push commits  

```
kubectl -n argocd-image-updater create secret generic git-creds --from-file=sshPrivateKey=<path/to/id_rsa>
```

## Kaniko

* create a secret for `kaniko` builds, for this you will need an `Opaque` secret:

```
 echo '{"auths":{"ghcr.io":{"auth":"****************"}}}' | kubectl create secret generic regcred-github-kaniko --from-file=config.json=/dev/stdin
 ```


## Use Contour

* disable `traefik`, see [article here](https://rancher.com/blog/2020/deploy-an-ingress-controllers)
* run `skaffold run --profile contour`
* make sure `cert-manager` is installed if you need `tls` ingresses
* expose `envoy` svc port on the router


