#!/usr/bin/bash

NAMESPACE=${1:-monitoring}

echo "Installing observability suite in namespace $NAMESPACE ..."

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && \
helm repo add grafana https://grafana.github.io/helm-charts && \
helm repo update && \
helm upgrade --install --values values/prometheus.yaml prometheus prometheus-community/prometheus --version "28.14.1" --namespace "$NAMESPACE" && \
kubectl rollout status deployment prometheus-server --namespace $NAMESPACE --timeout=300s && \
helm upgrade --install loki --values values/loki.yaml grafana/loki-stack --version "2.10.3" --namespace "$NAMESPACE" && \
kubectl rollout status statefulset loki --namespace $NAMESPACE --timeout=300s && \
helm upgrade --install --values values/grafana.yaml grafana grafana/grafana --version "10.5.15" --namespace "$NAMESPACE" && \
kubectl rollout status deployment grafana --namespace $NAMESPACE --timeout=300s && \
echo "#######################################" && \
echo "Observability Suite Deployment Complete" && \
echo "#######################################"