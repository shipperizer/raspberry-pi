# RaspberryPI setup

* install `Ubuntu Server 64bit` via `raspberryPi Imager`
* check Makefile `apt` target to install dependencies
* run `k3s` target to install K3s
** restart `k3s.service` and export `kubeconfig`
* add various `imagePullSecrets` secrets in `k8s`


## Use Contour

* disable `traefik`, see [article here](https://rancher.com/blog/2020/deploy-an-ingress-controllers)
* run `skaffold run --profile contour`
* make sure `cert-manager` is installed if you need `tls` ingresses
* expose `envoy` svc port on the router

## ArgoCD

* create a secret for `image-updater` builds, same as the one needed to pull images (which is in the default namespace):
```
echo '{"auths":{"ghcr.io":{"auth":"*****************"}}}' | kubectl create secret generic regcred-github --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin -n argocd
```
* port forward the service locally and follow the `Getting Started` guide [here](https://argoproj.github.io/argo-cd/getting_started/)

## Kaniko

* create a secret for `kaniko` builds, for this you will need an `Opaque` secret:

```
 echo '{"auths":{"ghcr.io":{"auth":"****************"}}}' | kubectl create secret generic regcred-github-kaniko --from-file=config.json=/dev/stdin
 ```


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