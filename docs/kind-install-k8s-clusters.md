# Install K8S clusters

## Create the clusters

```sh
kind create cluster --name dc1 --config kind/kind-dc1.yaml
kind create cluster --name dc2 --config kind/kind-dc2.yaml
```

## Get info about clusters
```sh
kind get clusters

# dc1
# dc2
```

## Stop clusters

kind nodes are Docker containers

- check running containers
```sh
docker ps

CONTAINER ID   IMAGE                  COMMAND                  CREATED       STATUS       PORTS                                                 NAMES
c77b771b044a   kindest/node:v1.29.2   "/usr/local/bin/entr…"   3 hours ago   Up 3 hours   127.0.0.1:53097->6443/tcp, 0.0.0.0:15002->32001/tcp   dc2-control-plane
3d839c5cc7ab   kindest/node:v1.29.2   "/usr/local/bin/entr…"   3 hours ago   Up 3 hours   127.0.0.1:59642->6443/tcp, 0.0.0.0:15001->32001/tcp   dc1-control-plane
```

- stop kind nodes
```sh
docker stop dc1-control-plane
docker stop dc2-control-plane
```

## Delete clusters

That completely removes:
- control plane container
- etcd data
- networking
- kubeconfig entry

```sh
# kind delete cluster --name <name>
kind delete cluster --name dc1
```
