# tailscale-operator

This chart is a wrapper around the upstream [Tailscale Kubernetes
operator](https://pkgs.tailscale.com/helmcharts) (`1.102.3`), pulled in as a
real versioned dependency rather than forked. It exists to layer on the
pieces upstream doesn't provide, without patching Tailscale's own templates:

- **Kyverno compliance.** `values.yaml` sets `operatorConfig.podLabels`
  (`application`, `env`, `team`, `email`, `slack_channel`) so the operator's
  pods carry the labels our Kyverno policies require. Upstream's operator
  Deployment has no `metadata.labels` hook, so there's no way to stamp
  Kyverno-required labels (or `kyverno-probes-policy: skip`) onto it from
  `values.yaml` alone; the downstream consumer (e.g. the Argo CD
  `Application`) is required to Kustomize-patch those onto the rendered
  Deployment, since this chart doesn't do it for you.
- **Workload identity federation.** `templates/oidc-discovery-rbac.yaml`
  optionally publishes this cluster's OIDC discovery/JWKS endpoints so
  Tailscale can validate the operator's ServiceAccount token, so clusters can
  run without a long-lived OAuth client secret.
- **Connectors, PeerRelays, and ProxyClasses on top of the operator.**
  Upstream ships the operator and CRDs; it doesn't create any `Connector`,
  `PeerRelay`, or `ProxyClass` resources for you. `templates/connectors.yaml`,
  `templates/peerrelays.yaml`, and `templates/proxyclasses.yaml` turn
  `values.yaml` entries into those CRs, plus a PDB per `ProxyClass`
  (`templates/proxyclass-pdb.yaml`) so different connector/peer relay types
  (e.g. an HA exit node vs. a subnet router vs. a peer relay) are never
  disrupted together.

## Usage

Each consumer is its own Argo CD Application (e.g.
`apps/sre/<cluster>-tailscale.yaml`) supplying its own tags and connectors.
A minimal HA exit-node setup:

```yaml
oidcDiscovery:
  enabled: true

proxyClasses:
  ci-exit:
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
    podDisruptionBudget:
      minAvailable: 1

connectors:
  - name: ci-exit-node
    replicas: 2
    proxyClass: ci-exit
    tags:
      - "tag:ci-exit"
    exitNode: true
```

See `values.yaml` for the full set of options and inline comments, including
`appConnector`/`subnetRouter` connectors and per-`ProxyClass` resource
overrides.

## Configuration

| Key | Default | Description |
| --- | --- | --- |
| `oidcDiscovery.enabled` | `false` | Publishes this cluster's OIDC discovery/JWKS endpoints to unauthenticated callers so the operator can authenticate via workload identity federation instead of an OAuth client secret. Set to `true` only for consumers using WIF. |
| `podMonitoring` | unset | Creates a GMP `PodMonitoring` scraping the operator's own controller-runtime metrics (`:8080/metrics`, on by default upstream, control plane not per-ProxyClass data plane). Set to `{}` to enable with the default interval, or `{interval: "15s"}` to override it. |
| `proxyClasses` | `{}` | Map of `tailscale.com/v1alpha1` ProxyClass name -> config. Each key gets its own `proxy-class` pod label, so PDBs and topology spread never mix connector types together. |
| `proxyClasses.<name>.topologySpreadConstraints` | unset | Spreads that ProxyClass's replicas across zones/nodes. `labelSelector` is filled in automatically from the ProxyClass name. |
| `proxyClasses.<name>.podDisruptionBudget` | unset | Creates a PDB scoped to that ProxyClass's pods (e.g. `minAvailable: 1`). Omit to leave that ProxyClass without a PDB. |
| `proxyClasses.<name>.resources` | unset | Resource requests/limits for the `tailscale` proxy container itself (not the operator). |
| `proxyClasses.<name>.env` | unset | Extra env vars for the `tailscale` proxy container, e.g. `TS_ENABLE_HEALTH_CHECK` (serves `/healthz` on `TS_LOCAL_ADDR_PORT`, default `[::]:9002`, shared with `TS_ENABLE_METRICS` if both are set and `TS_LOCAL_ADDR_PORT` isn't overridden). Each entry is `{name, value}` only, the ProxyClass CRD's `env` schema has no `valueFrom` field, so it can't source a value from a Secret/ConfigMap. |
| `proxyClasses.<name>.metrics.enable` | unset | Serves Prometheus metrics at `<pod-ip>:9002/metrics`, and names that container port `metrics`. Auto-sets `TS_LOCAL_ADDR_PORT`/`TS_ENABLE_METRICS`, so don't set `TS_LOCAL_ADDR_PORT` again under `env`. **No-op for a PeerRelay's ProxyClass** (confirmed against upstream source, `k8s-operator/reconciler/tailscaled`) -- set `env: TS_ENABLE_METRICS: "true"` there instead; the container port stays named `healthz` either way, since that's hardcoded by the PeerRelay reconciler. |
| `proxyClasses.<name>.podMonitoring` | unset | Creates a GMP `PodMonitoring` (this cluster uses GKE Managed Prometheus, not the Prometheus Operator, so no `ServiceMonitor`) scraping that metrics endpoint. Requires `metrics.enable: true`, or `podMonitoring.port` set explicitly (for a PeerRelay's ProxyClass, `port: healthz`, since `metrics.enable` is a no-op there). `selector` is filled in automatically; `port` defaults to `metrics`; `interval` defaults to `30s`. |
| `connectors` | `[]` | List of `tailscale.com/v1alpha1` Connector CRs to create. |
| `connectors[].name` | — (required) | Used as `metadata.name`, and as the default `connectors[].hostname`/`connectors[].hostnamePrefix`. |
| `connectors[].tags` | — (required) | Tailscale ACL tags applied to the node. |
| `connectors[].replicas` | `1` | `> 1` renders `hostnamePrefix` (HA, required for multiple replicas) instead of a fixed `hostname`. |
| `connectors[].hostname` / `hostnamePrefix` | defaults to `.name` | Override the auto-derived hostname. Use `hostname` for `replicas: 1`, `hostnamePrefix` for HA. |
| `connectors[].proxyClass` | unset | References a key under `proxyClasses` to apply that spread/PDB/resources config to this Connector. Must match a `proxyClasses` key when set. |
| `connectors[].exitNode` | `false` | Advertises the Connector as an exit node. Mutually exclusive with `appConnector`. |
| `connectors[].subnetRouter` | unset | `advertiseRoutes` for subnet routing (required, non-empty). Mutually exclusive with `appConnector`. |
| `connectors[].appConnector` | unset | App connector config (e.g. `routes`). Mutually exclusive with `exitNode`/`subnetRouter`. |
| `peerRelays` | `[]` | List of `tailscale.com/v1alpha1` PeerRelay CRs to create. Lets two tailnet nodes that can't reach each other directly relay traffic through a third node instead of falling back to DERP. https://tailscale.com/kb/1115/high-availability |
| `peerRelays[].name` | — (required) | Used as `metadata.name`, and as the default `peerRelays[].hostnamePrefix`. |
| `peerRelays[].hostnamePrefix` | defaults to `.name` | Every PeerRelay replica gets this prefix plus its StatefulSet ordinal appended (there's no singular `hostname` field, unlike Connector -- it's always rendered). |
| `peerRelays[].replicas` | unset (operator defaults to `1`) | Set to enable HA peer relays. |
| `peerRelays[].tags` | unset (operator defaults to `[tag:k8s]`) | Tailscale ACL tags applied to the node. |
| `peerRelays[].proxyClass` | unset | References a key under `proxyClasses` to apply that spread/PDB/resources config to this PeerRelay. Must match a `proxyClasses` key when set. |
| `peerRelays[].tailnet` | unset | Tailnet this PeerRelay should join, if not the default. Immutable once set. |
| `peerRelays[].service` / `aws` | unset | Passed through as-is; see the PeerRelay CRD for `service.annotations` and AWS Elastic IP pinning. |

A `proxyClasses` entry referenced by a `peerRelays[].proxyClass` must **not** set `env: TS_ENABLE_HEALTH_CHECK` -- the operator's `peerrelay-reconciler` injects that itself (each PeerRelay replica has its own LoadBalancer Service needing a health check), and a duplicate entry makes the StatefulSet apply fail outright, silently, with no pods ever created.

The `tailscale-operator.*` keys (operator image, `operatorConfig`, `ingressClass`,
etc.) pass straight through to the upstream subchart — see [its own
values.yaml](https://github.com/tailscale/tailscale/blob/main/cmd/k8s-operator/deploy/chart/values.yaml)
for the full set.

## How it works

- `connectors[]` entries render one `Connector` CR each. `tags` is required;
  `appConnector` is mutually exclusive with `exitNode`/`subnetRouter`; a
  `replicas` value greater than 1 renders `hostnamePrefix` instead of
  `hostname` (HA Connectors require a prefix, not a fixed hostname).
- `peerRelays[]` entries render one `PeerRelay` CR each. Unlike Connector,
  `hostnamePrefix` is always rendered (defaulting to `.name`), since PeerRelay
  has no singular `hostname` field.
- `proxyClasses` is a map, one `ProxyClass` per key. Each key gets its own
  `proxy-class` pod label (not `app`, which the operator manages itself and
  sets to the parent's UID), so `topologySpreadConstraints` and the sibling PDB's
  selector only ever target that ProxyClass's own pods.
- `oidcDiscovery.enabled` toggles the `ClusterRoleBinding` in
  `oidc-discovery-rbac.yaml`. `ClusterRoleBinding` is cluster-scoped, and
  Helm doesn't enforce release-name uniqueness across namespaces, so its
  name includes both the release name and namespace
  (`{{ include "tailscale-operator.fullname" . }}-{{ .Release.Namespace }}-oidc-discovery`)
  to avoid colliding with another install of this chart in the same
  cluster.

Run `helm unittest charts/tailscale-operator` to exercise this branching
logic (see `tests/`).
