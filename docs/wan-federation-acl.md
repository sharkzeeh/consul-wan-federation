# consul-k8s: WAN Federation Between Multiple Kubernetes Clusters with ACLs enabled

Links:
- [WAN Federation Between Multiple Kubernetes Clusters Through Mesh Gateways](https://developer.hashicorp.com/consul/docs/east-west/wan-federation/k8s)

**NOTE**: See `wan-federation.md` for quick start


## Install / upgrade consul-k8s to enable ACLs

- show k8s contexts
```sh
kubectl config get-contexts
CURRENT  NAME   CLUSTER   AUTHINFO  NAMESPACE
*        dc1    dc1       dc1
         dc2    dc2       dc2
```

- install / upgrade primary (dc1) with / to ACL mode
```sh
kubectl config use-context dc1

helm upgrade --install consul hashicorp/consul -n consul --create-namespace -f helm/values-dc1-acl.yaml
```

- export consul federation secret from the primary consul cluster (dc1); mind the new field `replicationToken`
```sh
kubectl --context dc1 -n consul get secret consul-federation
# NAME                TYPE     DATA   AGE
# consul-federation   Opaque   4      4d1h

kubectl --context dc1 -n consul get secret consul-federation -o yaml > consul-federation.yaml
```

- import updated federation secret into secondary (dc2); delete the previous one if it exists
```sh
kubectl config use-context dc2

kubectl --context dc2 get ns consul || kubectl --context dc2 create ns consul

# delete if "consul-federation" secret exists
# kubectl --context dc2 -n consul delete secret consul-federation

kubectl --context dc2 -n consul apply -f consul-federation.yaml
```

- install / upgrade secondary (dc2) with / to ACL mode
```sh
helm upgrade --install consul hashicorp/consul -n consul --create-namespace -f helm/values-dc2-acl.yaml --version "1.9.3"
```

## Verifying Federation

- consul members
```sh
# dc1
kubectl --context dc1 -n consul exec statefulset/consul-server -- consul members -wan
Node                 Address           Status  Type    Build   Protocol  DC   Partition  Segment
consul-server-0.dc1  10.241.0.17:8302  alive   server  1.22.2  2         dc1  default    <all>
consul-server-0.dc2  10.242.0.33:8302  alive   server  1.22.2  2         dc2  default    <all>

# dc2
kubectl --context dc2 -n consul exec statefulset/consul-server -- consul members -wan
Node                 Address           Status  Type    Build   Protocol  DC   Partition  Segment
consul-server-0.dc1  10.241.0.17:8302  alive   server  1.22.2  2         dc1  default    <all>
consul-server-0.dc2  10.242.0.33:8302  alive   server  1.22.2  2         dc2  default    <all>
```

- verify Service Resolver upstream (call service in dc2 from a client pod in dc1)
```sh
kubectl --context dc1 -n default exec -c client deploy/client -- curl -s localhost:1234
hello-from-dc2
```

## Verify ACLs

- get bootstrap token from primary dc (dc1)
```sh
kubectl --context dc1 -n consul get secrets/consul-bootstrap-acl-token
NAME                         TYPE     DATA   AGE
consul-bootstrap-acl-token   Opaque   1      13m

kubectl --context dc1 -n consul get secrets/consul-bootstrap-acl-token --template={{.data.token}} | base64 -d
# <CONSUL_BOOTSTRAP_ACL_TOKEN>
```

- list ACL tokens
```sh
kubectl --context dc1 -n consul exec -it statefulset/consul-server -- sh

$ consul acl token list
Failed to retrieve the token list: Unexpected response code: 403 (Permission denied: anonymous token lacks permission 'acl:read'. The anonymous token is used implicitly when a request does not specify a token.)

$ export CONSUL_HTTP_TOKEN="<CONSUL_BOOTSTRAP_ACL_TOKEN>"
$ export CONSUL_HTTP_ADDR="https://localhost:8501"

$ consul acl token list
...

AccessorID:       1405ac08-a153-8af4-8fda-fefd48eca75f
SecretID:         XXX
Description:      Bootstrap Token (Global Management)
Local:            false
Create Time:      2026-03-03 14:43:30.094574833 +0000 UTC
Policies:
   00000000-0000-0000-0000-000000000001 - global-management

AccessorID:       00000000-0000-0000-0000-000000000002
SecretID:         anonymous
Description:
Local:            false
Create Time:      2026-03-03 14:41:28.160974085 +0000 UTC
Policies:
   0c8b6d02-c893-812a-0c17-a08c512c0e07 - anonymous-token-policy

AccessorID:       28ab179e-eb5a-d427-4f89-9904a09e6b4c
SecretID:         XXX
Description:      acl-replication-token Token
Local:            false
Create Time:      2026-03-03 14:43:30.424408889 +0000 UTC
Policies:
   f56b6a56-9815-b745-5625-d1b165636df6 - acl-replication-token

AccessorID:       fb9359b1-8f10-d97b-7301-6021617f4c10
SecretID:         XXX
Description:      token created via login: {"component":"connect-injector","pod":"consul/consul-connect-injector-569b7cbc8b-g8d4m"}
Local:            true
Auth Method:      consul-k8s-component-auth-method (Namespace: )
Create Time:      2026-03-03 14:43:31.708642633 +0000 UTC
Roles:
   bef3d7a3-661a-5704-b939-e7715392f18a - consul-connect-inject-acl-role

...
```

- the same token is applicable in secondary datacenters (dc2, etc.)
