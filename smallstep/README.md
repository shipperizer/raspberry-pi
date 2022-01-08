1. Get the PKI and Provisioner secrets running these commands:
   kubectl get -n default -o jsonpath='{.data.password}' secret/step-certificates-ca-password | base64 --decode
   kubectl get -n default -o jsonpath='{.data.password}' secret/step-certificates-provisioner-password | base64 --decode

2. Get the CA URL and the root certificate fingerprint running this command:
   kubectl -n default logs job.batch/step-certificates

3. Delete the configuration job running this command:
   kubectl -n default delete job.batch/step-certificates


Patch `configmap` with `ca.json` with https://github.com/smallstep/certificates/issues/279#issuecomment-634984725 (FileIO)



# on Host

Run:

```
kubectl get configmaps step-certificates-certs -o json | jq '.data["root_ca.crt"]' -r > root_ca.crt
```


Refer to https://smallstep.com/blog/istio-with-private-ca/ and follow steps

```
kubectl get -o jsonpath="{.data['root_ca\.crt']}" configmaps/step-certificates-certs -n istio-system | tr -d '\n' | base64
XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX==
acabbia@ldcl141282m  on  main!16:45:16 π  kubectl get -o jsonpath="{.data['ca\.json']}" configmaps/step-certificates-config -n istio-system | jq .authority.provisioners
[
  {
    "type": "JWK",
    "name": "admin",
    "key": {
      "use": "sig",
      "kty": "EC",
      "kid": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
      "crv": "P-256",
      "alg": "ES256",
      "x": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
      "y": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    },
    "encryptedKey": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  }
]
```