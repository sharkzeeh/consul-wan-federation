# Service-to-Service communcation accross Consul datacenters

## Check that both kind clusters share the same Docker network

```sh
kubectl --context dc2 get nodes -o wide
NAME                STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION                     CONTAINER-RUNTIME
dc2-control-plane   Ready    control-plane   9d    v1.29.2   172.18.0.3    <none>        Debian GNU/Linux 12 (bookworm)   6.6.87.2-microsoft-standard-WSL2   containerd://1.7.13
```

```sh
docker network inspect kind --format '{{json .Containers}}'
{"3d839c5cc7abcc5d4b87f388197aab5fc7b09f58bbbdba05188032f64c99c857":{"Name":"dc1-control-plane","EndpointID":"97c42accb61238f8cf571e0daa37cc36dcbfdc7e7e6fb88ee55ff64a92ca9b4d","MacAddress":"ce:77:fb:a9:ff:2c","IPv4Address":"172.18.0.3/16","IPv6Address":"fc00:f853:ccd:e793::3/64"},"c77b771b044af60e5c8fbbe50fa00cf061d9e668a96a41920b3d86107652c3b6":{"Name":"dc2-control-plane","EndpointID":"5a754d51008eaa2461d4eadbe3eabff888300418c0ecb2a4c6098f9ccb29c228","MacAddress":"32:dd:3f:4c:aa:1d","IPv4Address":"172.18.0.2/16","IPv6Address":"fc00:f853:ccd:e793::2/64"}}
```
You should see entries for both `dc1-control-plane` and `dc2-control-plane`. If they’re on different networks, `172.18.0.3` won't be routable cross-cluster.

That output is specifically for the Docker network named kind, and it shows:
- `dc1-control-plane`: `172.18.0.3/16`
- `dc2-control-plane`: `172.18.0.2/16`
Same subnet (`172.18.0.0/16`), so not different networks.

What this means for visibility

From containers/pods that can route to the Docker kind network (including pods in the other kind cluster), 172.18.0.3:6443 should be reachable.
So `global.federation.k8sAuthMethodHost: "https://172.18.0.3:6443"` is the right kind-local style value to try.

Quick proof (from inside dc1)

> Run the command and if you get `ok`, then the address is visible from the primary cluster, which is the requirement for ACL-enabled federation:

- primary cluster
```sh
kubectl --context dc1 -n consul run curl --rm -it --restart=Never --image=curlimages/curl:8.6.0 -- sh 
# inside the pod
# kubectl --context dc1 -n consul exec -it curl -- sh
$ curl -k https://172.18.0.3:6443/readyz
ok

kubectl --context dc2 -n consul run curl --rm -it --restart=Never --image=curlimages/curl:8.6.0 -- curl -w "\n" -k https://172.18.0.3:6443/readyz
ok
```
- secondary cluster
```sh
kubectl --context dc2 -n consul run curl --rm -it --restart=Never --image=curlimages/curl:8.6.0 -- curl -w "\n" -k https://172.18.0.3:6443/readyz
ok
```

That `ok` response proves pods in `dc1` can reach the `dc2` Kubernetes API at 172.18.0.3:6443, which is exactly what federation.k8sAuthMethodHost needs when ACLs are enabled.

---

### check kind node access via `host.docker.internal`

- test secondary cluster
```sh
kubectl --context dc2 config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
https://127.0.0.1:53097

kubectl --context dc2 -n consul run curl --rm -it --restart=Never --image=curlimages/curl:8.6.0 -- curl -w "\n" -k https://host.docker.internal:53097/readyz
ok
pod "curl" deleted from consul namespace
```
- test primary cluster
```sh
kubectl --context dc1 config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
https://127.0.0.1:59642

kubectl --context dc2 -n consul run curl --rm -it --restart=Never --image=curlimages/curl:8.6.0 -- curl -w "\n" -k https://host.docker.internal:59642/readyz
ok
pod "curl" deleted from consul namespace
```

### check kind node access via container name

- get kind docker container names
```sh
kind get clusters && echo "---" && kind get nodes --name dc1 && kind get nodes --name dc2
dc1
dc2
---
dc1-control-plane
dc2-control-plane
```

- run test against container name
```sh
kubectl --context dc2 -n consul run curl --rm -it --restart=Never --image=curlimages/curl:8.6.0 -- curl -w "\n" -k https://dc1-control-plane:6443/readyz
ok
pod "curl" deleted from consul namespace
```

## Debug service communication

### kube-dns (same cluster)

NOTES:
- echo: `consul.hashicorp.com/connect-inject: "true"`
- echo2: `consul.hashicorp.com/connect-inject: "false"`
- netshoot: `consul.hashicorp.com/connect-inject: "true"`
- netshoot2: `consul.hashicorp.com/connect-inject: "false"`

Deploy apps in dc2 for tests
```sh
kubectl --context dc2 -n default apply -f apps/dc2-echo.yaml
kubectl --context dc2 -n default apply -f apps/dc2-echo2.yaml
kubectl --context dc2 -n default apply -f apps/netshoot-deploy.yaml
kubectl --context dc2 -n default apply -f apps/netshoot-deploy2.yaml
```

#### Scenario 1: Deploy "echo" app `consul.hashicorp.com/connect-inject: "true"` and "netshoot" app `consul.hashicorp.com/connect-inject: "false"`

- run tests
```sh
kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- curl -s echo.default.svc.cluster.local:5678
curl: (52) Empty reply from server

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- curl -s echo2.default.svc.cluster.local:5678
hello-from-echo2

# --- nslookup ---
kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- nslookup echo.service.consul.
Server:         10.98.0.10
Address:        10.98.0.10#53

** server cannot find echo.service.consul: NXDOMAIN

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- nslookup echo.service.consul. 127.0.0.1
;; communications error to 127.0.0.1#53: connection refused
;; no servers could be reached

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- nslookup echo.service.consul. consul-dns.consul
Server:         consul-dns.consul
Address:        10.98.183.130#53

Name:   echo.service.consul
Address: 10.242.0.9

# --- dig ---

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot -- dig +short echo.service.consul
# empty reply 

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot -- dig +short @consul-dns.consul echo.service.consul
10.242.0.9
```

#### Scenario 2: Deploy "echo" and "netshoot" apps with annotation `consul.hashicorp.com/connect-inject: "true"`

- run tests
```sh
kubectl --context dc2 -n default exec -c netshoot deploy/netshoot -- curl -s echo.default.svc.cluster.local:5678
hello-from-dc2

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot -- curl -s echo2.default.svc.cluster.local:5678
hello-from-echo2

# --- nslookup ---
kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- nslookup echo.service.consul. consul-dns.consul
;; Got recursion not available from 127.0.0.1, trying next server
Server:         10.98.0.10
Address:        10.98.0.10#53

** server cannot find echo.service.consul: NXDOMAIN

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- nslookup echo.service.consul. 127.0.0.1
Server:         127.0.0.1
Address:        127.0.0.1#53

Name:   echo.service.consul
Address: 10.242.0.9

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot2 -- nslookup echo.service.consul. consul-dns.consul
Server:         127.0.0.1
Address:        127.0.0.1#53

Name:   echo.service.consul
Address: 10.242.0.9

# --- dig ---

kubectl --context dc2 -n default exec -c netshoot deploy/netshoot -- dig +short echo.service.consul
10.242.0.9
```

## Enable connectivity between k8s services across multiple datacenters

### Service Resolver and Upstream annotation

dc2 deploy and dc1 serviceresolver
```sh
kubectl --context dc2 -n default apply -f apps/dc2-echo.yaml
kubectl --context dc1 -n default apply -f apps/dc1-echo-resolver.yaml
```

client in dc1
```sh
kubectl --context dc1 -n default apply -f apps/dc1-client.yaml
```

Test: curl dc2 service from pod in dc1
```sh
kubectl --context dc1 -n default exec -it deploy/client -- curl -sS http://127.0.0.1:1234

$ curl -sS http://127.0.0.1:1234
hello-from-dc2
```

## Looking virtual services

Enterpise edition only !!! :(

Links:
- https://developer.hashicorp.com/consul/docs/discover/service/static#service-lookups-for-consul-enterprise
- https://developer.hashicorp.com/consul/docs/manage-traffic/virtual-service#configure-your-application-to-call-the-dns

```sh
http://virtual-api.virtual.consul/
```
