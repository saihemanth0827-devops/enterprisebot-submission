#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER_NAME="demo"
IMAGE="demo-service:1.0.0"
NAMESPACE="demo"
RELEASE="demo"
INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml"

for cmd in docker kind kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: required command not found: $cmd" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not available. Start Docker Desktop/Engine first." >&2; exit 1; }

if ! kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
  config_file="$(mktemp)"
  trap 'rm -f "$config_file"' EXIT
  cat > "$config_file" <<'KIND'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    labels:
      ingress-ready: "true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
KIND
  kind create cluster --name "$CLUSTER_NAME" --config "$config_file" --wait 120s
else
  echo "kind cluster '$CLUSTER_NAME' already exists; reusing it."
fi
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# The upstream kind-specific manifest configures host ports and admission jobs.
kubectl apply -f "$INGRESS_MANIFEST"
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s

# Build and load on every run so the cluster has the current local source image.
docker build -t "$IMAGE" ./service
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

helm upgrade --install "$RELEASE" ./chart \
  --namespace "$NAMESPACE" --create-namespace \
  --set image.repository=demo-service \
  --set image.tag=1.0.0 \
  --wait --timeout 180s

echo
echo "Setup complete. Verify with:"
echo "  kubectl -n ${NAMESPACE} get deploy,pods,svc,ingress"
echo "  curl -H 'Host: demo.local' http://127.0.0.1/"
echo "  curl -H 'Host: demo.local' http://127.0.0.1/healthz"
