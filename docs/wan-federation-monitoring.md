# Monitoring

Links:
- https://developer.hashicorp.com/consul/docs/observe/telemetry/k8s#metrics-in-the-ui-topology-visualization
- https://developer.hashicorp.com/consul/docs/observe/telemetry/vm

## Built-in demo prometheus

<!-- Default prometheus version `prometheus-13.2.1` -->

- dc1 (install custom helm chart + apply specific *ProxyDefaults*)
```sh
kubectl config use-context dc1

helm --kube-context dc1 upgrade --install consul hashicorp/consul -n consul --create-namespace -f helm/values-dc1-acl-monitoring.yaml --version "1.9.3"
```

**NOTE**: important to use updated `ProxyDefaults` object for dc1

- https://developer.hashicorp.com/consul/docs/monitor/telemetry/dataplane
- https://developer.hashicorp.com/consul/docs/reference/config-entry/proxy-defaults#prometheus

> To enable telemetry for Consul Dataplane, enable telemetry for Envoy by specifying an external metrics store in the proxy-defaults configuration entry or directly in the proxy.config field of the proxy service definition

```yaml
spec:
  ...
  config:
    envoy_prometheus_bind_addr: '0.0.0.0:20200'
```

```sh
kubectl -n consul apply -f proxydefaults/proxydefaults-monitoring.yaml
```

- dc2
```sh
# kubectl config use-context dc2

helm --kube-context dc2 upgrade --install consul hashicorp/consul -n consul --create-namespace -f helm/values-dc2-acl-monitoring.yaml --version "1.9.3"
```

- access prometheus server
```sh
kubectl -n consul port-forward svc/prometheus-server 9090:80
```

**NOTE**: you will see L4-oriented view (see below)

### L7 metrics (HTTP, gRPC)

Links:
- https://developer.hashicorp.com/consul/docs/observe/telemetry/k8s#metrics-in-the-ui-topology-visualization

- to see L7-oriented view (RPS, ER, MED, P99 ...) make sure *ServiceDefaults* objects are applied (per-service)
```sh
kubectl --context dc1 -n consul apply -f apps/dc1-service-defaults.yaml
kubectl --context dc2 -n consul apply -f apps/dc2-service-defaults.yaml
```

- generate real HTTP calls to the upstream through the mesh
```sh
kubectl --context dc1 -n default exec deploy/client -c client -- curl -sS http://127.0.0.1:1234
```

**NOTE**: those metrics can be observed in different ways:
1. Query Prometheus
```sh
kubectl -n consul port-forward svc/prometheus-server 9090:80
```

Open `localhost:9090/graph`
```sh
count({__name__=~"envoy_cluster_upstream_rq_.*"})

envoy_cluster_upstream_rq_completed
```

2. Envoy admin (per-service)
```sh
kubectl --context dc1 -n default port-forward deploy/client 19000:19000

curl http://127.0.0.1:19000/stats/prometheus
```

Look for `envoy_cluster_upstream_rq`

3. Scrape listener (per-service)
```sh
kubectl --context dc1 -n default port-forward deploy/client 20200:20200

curl http://localhost:20200/metrics
```

Look for `envoy_cluster_upstream_rq`

### L4 metrics (TCP)

To see L4-style metrics (bps, CR / RX / TX / NR) omit *ServiceDefaults* for a given service (Consul/Envoy default to TCP for many workloads), or set `protocol: tcp` explicitly on *ServiceDefaults*

## Custom monitoring

- dc1 (install monitoring suite + install custom helm chart + apply specific *ProxyDefaults*)
```sh
kubectl config use-context dc1

./monitoring/install-observability-suite-v2.sh monitoring

# make sure to use  previous monitoring
helm --kube-context dc1 upgrade --install consul hashicorp/consul -n consul --create-namespace -f helm/values-dc1-acl-monitoring-custom.yaml --version "1.9.3"

kubectl -n consul apply -f proxydefaults/proxydefaults-monitoring.yaml
```

- dc2
```sh
kubectl config use-context dc2

./monitoring/install-observability-suite-v2.sh monitoring

helm --kube-context dc2 upgrade --install consul hashicorp/consul -n consul --create-namespace -f helm/values-dc2-acl-monitoring-custom.yaml --version "1.9.3"
```
