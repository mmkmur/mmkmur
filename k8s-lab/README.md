# Local Kubernetes Lab (kind)

Free, local, multi-node Kubernetes cluster running as Docker containers via [kind](https://kind.sigs.k8s.io/).

## Stack
- Docker Desktop (already installed)
- `kind` v0.32.0 (installed via `winget install Kubernetes.kind`)
- `kubectl` v1.34.1 (already installed)
- Cluster: `k8s-lab` — 1 control-plane + 2 worker nodes, k8s v1.36.1

## Config
Cluster topology lives in [`kind-config.yaml`](kind-config.yaml). Ports 8080/8443 on
the host are mapped to the control-plane node (80/443) for later ingress use.

## Common commands

```bash
# Start the cluster (already created)
kind create cluster --config kind-config.yaml

# Point kubectl at it
kubectl config use-context kind-k8s-lab

# Tear down when done (frees Docker resources)
kind delete cluster --name k8s-lab

# Recreate later, same command as above
kind create cluster --config kind-config.yaml
```

## Note on TLS / Norton
Norton Antivirus's network-filter driver intercepts TLS on 127.0.0.1, so kubectl's
built-in CA check on the kind API server fails with `x509: certificate signed by
unknown authority`. Fixed for this cluster only via:

```bash
kubectl config set-cluster kind-k8s-lab --insecure-skip-tls-verify=true
```

This is safe for a loopback-only local dev cluster. If you ever see the same TLS
error on other local tools, it's Norton, not the tool.

## Suggested next steps
- `kubectl apply -f <manifest>` — deploy your own workloads
- Install [k9s](https://k9scli.io/) (`winget install derailed.k9s`) for a terminal UI
- Add `ingress-nginx` if you want to test Ingress locally (works with the 8080/8443 port mappings above)
- `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` for `kubectl top`
