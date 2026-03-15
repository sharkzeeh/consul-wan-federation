# Misc

## Network debug

- quick debug networking (nslookup)

```sh
kubectl -n consul run -it --rm dns-test --image=busybox:1.36 --restart=Never -- sh
```

- quick debug networking (nslookup / curl)
```sh
kubectl -n consul run -it --rm curl --image=curlimages/curl -- sh
```

## Check ProxyDefaults

- from secondary cluster check `MeshGateway.Mode`
```sh
kubectl --context dc2 -n consul exec statefulset/consul-server --namespace consul -- consul config read -kind proxy-defaults -name global
Defaulted container "consul" out of: consul, locality-init (init)
{
    "Kind": "proxy-defaults",
    "Name": "global",
    "TransparentProxy": {},
    "MeshGateway": {
        "Mode": "local"
    },
    "Expose": {},
    "AccessLogs": {},
    "Meta": {
        "consul.hashicorp.com/source-datacenter": "dc1",
        "external-source": "kubernetes"
    },
    "CreateIndex": 1257,
    "ModifyIndex": 1257
}
```

## Pod annotations

Links:
- [Consul Service Mesh annotations](https://developer.hashicorp.com/consul/docs/reference/k8s/annotation-label?page=k8s&page=annotations-and-labels#annotations)
- [Consul Service Sync annotations](https://developer.hashicorp.com/consul/docs/register/service/k8s/service-sync#service-name)
