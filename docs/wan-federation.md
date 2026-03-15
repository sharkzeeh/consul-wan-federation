# consul-k8s: WAN Federation Between Multiple Kubernetes Clusters

Links:
- [WAN Federation Between Multiple Kubernetes Clusters Through Mesh Gateways](https://developer.hashicorp.com/consul/docs/east-west/wan-federation/k8s)

## Install consul-k8s

- show k8s contexts
```sh
kubectl config get-contexts
CURRENT  NAME   CLUSTER   AUTHINFO  NAMESPACE
*        dc1    dc1       dc1
         dc2    dc2       dc2
```

### Node Port solution
- install consul-k8s in the first k8s cluster (primary dc)
```sh
kubectl config use-context dc1

helm install consul hashicorp/consul --namespace consul --create-namespace -f helm/values-dc1.yaml --version "1.9.3"
# helm upgrade --install consul hashicorp/consul --namespace consul --create-namespace -f helm/values-dc1.yaml --version "1.9.3"
```

- export consul federation secret from the first consul k8s cluster (primary consul dc - ***dc1***)
```sh
kubectl --context dc1 -n consul get secret consul-federation
# NAME                TYPE     DATA   AGE
# consul-federation   Opaque   3      49m

kubectl --context dc1 -n consul get secret consul-federation -o yaml > consul-federation.yaml
```

- apply cluster federation secret and install consul in the second k8s cluster (secondary consul dc - ***dc2***)
```sh
kubectl config use-context dc2

kubectl --context dc2 get ns consul || kubectl --context dc2 create ns consul

kubectl --context dc2 -n consul apply -f consul-federation.yaml
# secret/consul-federation created

helm install consul hashicorp/consul --namespace consul --create-namespace -f helm/values-dc2.yaml --version "1.9.3"
# helm upgrade --install consul hashicorp/consul --namespace consul --create-namespace -f helm/values-dc2.yaml --version "1.9.3"
```

---

✅ 1️⃣ The Federation Secret (source of truth)

This is the primary source of configuration.

In dc2, run:
```sh
kubectl --context dc2 -n consul get secret consul-federation -o jsonpath='{.data.serverConfigJSON}' | base64 -d; echo
```

This prints something like:
```json
{"primary_datacenter":"dc1","primary_gateways":["dc1-control-plane:32001"]}
```

If you still see:
```
"primary_gateways":["192.0.2.2:32001"]
```

then dc2 is definitely configured wrong.

This is the most important place to check.


✅ 2️⃣ The Consul server runtime config (what it actually loaded)

In dc2:

```sh
kubectl --context dc2 -n consul exec -it consul-server-0 -- consul operator raft list-peers
```

Then check WAN join status:
```sh
kubectl --context dc2 -n consul exec -it consul-server-0 -- consul members -wan
```

✅ 3️⃣ Inspect the actual mounted server config inside the pod

The federation secret is mounted into the server pod.

You can inspect it directly:
```sh
kubectl --context dc2 -n consul exec -it consul-server-0 -- cat /consul/userconfig/consul-federation/serverConfigJSON
```

This shows exactly what the running server is reading.

If that file contains 192.0.2.2, then:

Either you didn’t re-apply the secret

Or the server pod hasn’t been restarted after secret update

Remember: Kubernetes does NOT automatically restart pods when a mounted Secret changes.

You must delete the server pod manually:
```sh
kubectl --context dc2 -n consul delete pod consul-server-0
```
🔍 4️⃣ Where the 192.0.2.2 specifically appears

You already saw it here (`consul-mesh-gateway` / `consul-server` pod):
```
joining: wan_addresses=["*.dc1/192.0.2.2"]
```

That line comes from the Consul server log during WAN join attempts.

That is runtime confirmation of what address it is trying to use.

---

- first cluster
```sh
helm install consul hashicorp/consul --namespace consul --create-namespace -f helm/values-dc1.yaml --version "1.9.3"
```
determine the Kubernetes API URL

save secret
```sh
kubectl get secret consul-federation --namespace consul --output yaml > consul-federation-secret.yaml
```

```sh
# primary cluster only
kubectl -n consul apply -f proxydefaults/proxydefaults.yaml
```

- second cluster

k8s api url?
```sh
$ export CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name == \"$(kubectl config current-context)\")].context.cluster}")
$ kubectl config view -o jsonpath="{.clusters[?(@.name == \"$CLUSTER\")].cluster.server}"
https://<some-url>
```


kubectl config use-context dc2
kubectl apply --filename consul-federation-secret.yaml

helm install consul hashicorp/consul --namespace consul --create-namespace -f helm/values-dc2.yaml --version "1.9.3"


#### Verifying Federation

- consul members
```sh
# dc1
kubectl --context dc1 -n consul exec statefulset/consul-server --namespace consul -- consul members -wan
Node                 Address          Status  Type    Build   Protocol  DC   Partition  Segment
consul-server-0.dc1  10.241.0.4:8302  alive   server  1.22.2  2         dc1  default    <all>
consul-server-0.dc2  10.242.0.7:8302  alive   server  1.22.2  2         dc2  default    <all>

# dc2
kubectl --context dc2 -n consul exec statefulset/consul-server --namespace consul -- consul members -wan
Node                 Address          Status  Type    Build   Protocol  DC   Partition  Segment
consul-server-0.dc1  10.241.0.4:8302  alive   server  1.22.2  2         dc1  default    <all>
consul-server-0.dc2  10.242.0.7:8302  alive   server  1.22.2  2         dc2  default    <all>
```

- consul catalog services
You can also use the `consul catalog services` command with the `-datacenter` flag to ensure each datacenter can read each other's services. In this example, our kubectl context is `dc1` and we're querying for the list of services in `dc2`:

dc1 -> dc2
```sh
$ kubectl --context dc1 -n consul exec statefulset/consul-server --namespace consul -- consul catalog services -datacenter dc2
consul
mesh-gateway
```

dc2 -> dc1
```sh
$ kubectl --context dc2 -n consul exec statefulset/consul-server --namespace consul -- consul catalog services -datacenter dc1
consul
mesh-gateway
```

---


### Load Balancer solution

TBD
