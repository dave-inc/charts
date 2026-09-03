# tailscale-operator

This chart is a wrapper around the upstream [Tailscale Kubernetes
operator](https://pkgs.tailscale.com/helmcharts) (`1.102.3`), pulled in as a
real versioned dependency rather than forked. It exists to layer on the
pieces upstream doesn't provide, without patching Tailscale's own templates:

- **Kyverno compliance.** Upstream's operator Deployment has no
  `metadata.labels` hook, so there's no way to stamp Kyverno-required labels
  (or `kyverno-probes-policy: skip`) onto it from `values.yaml` alone. This
  wrapper Kustomize-patches those labels onto the rendered Deployment after
  the subchart renders it.
- **Workload identity federation.** `templates/oidc-discovery-rbac.yaml`
  optionally publishes this cluster's OIDC discovery/JWKS endpoints so
  Tailscale can validate the operator's ServiceAccount token, so clusters can
  run without a long-lived OAuth client secret.
- **Connectors and ProxyClasses on top of the operator.** Upstream ships the
  operator and CRDs; it doesn't create any `Connector` or `ProxyClass`
  resources for you. `templates/connectors.yaml` and
  `templates/proxyclasses.yaml` turn `values.yaml` entries into those CRs,
  plus a PDB per `ProxyClass` (`templates/proxyclass-pdb.yaml`) so different
  connector types (e.g. an HA exit node vs. a subnet router) are never
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
| `proxyClasses` | `{}` | Map of `tailscale.com/v1alpha1` ProxyClass name -> config. Each key gets its own `app` pod label, so PDBs and topology spread never mix connector types together. |
| `proxyClasses.<name>.topologySpreadConstraints` | unset | Spreads that ProxyClass's replicas across zones/nodes. `labelSelector` is filled in automatically from the ProxyClass name. |
| `proxyClasses.<name>.podDisruptionBudget` | unset | Creates a PDB scoped to that ProxyClass's pods (e.g. `minAvailable: 1`). Omit to leave that ProxyClass without a PDB. |
| `proxyClasses.<name>.resources` | unset | Resource requests/limits for the `tailscale` proxy container itself (not the operator). |
| `connectors` | `[]` | List of `tailscale.com/v1alpha1` Connector CRs to create. |
| `connectors[].name` | — (required) | Used as `metadata.name`, and as the default `hostname`/`hostnamePrefix`. |
| `connectors[].tags` | — (required) | Tailscale ACL tags applied to the node. |
| `connectors[].replicas` | `1` | `> 1` renders `hostnamePrefix` (HA, required for multiple replicas) instead of a fixed `hostname`. |
| `connectors[].hostname` / `hostnamePrefix` | defaults to `.name` | Override the auto-derived hostname. Use `hostname` for `replicas: 1`, `hostnamePrefix` for HA. |
| `connectors[].proxyClass` | unset | References a key under `proxyClasses` to apply that spread/PDB/resources config to this Connector. |
| `connectors[].exitNode` | `false` | Advertises the Connector as an exit node. Mutually exclusive with `appConnector`. |
| `connectors[].subnetRouter` | unset | `advertiseRoutes` for subnet routing. Mutually exclusive with `appConnector`. |
| `connectors[].appConnector` | unset | App connector config (e.g. `routes`). Mutually exclusive with `exitNode`/`subnetRouter`. |

The `tailscale-operator.*` keys (operator image, `operatorConfig`, `ingressClass`,
etc.) pass straight through to the upstream subchart — see [its own
values.yaml](https://github.com/tailscale/tailscale/blob/main/cmd/k8s-operator/deploy/chart/values.yaml)
for the full set.

## How it works

- `connectors[]` entries render one `Connector` CR each. `tags` is required;
  `appConnector` is mutually exclusive with `exitNode`/`subnetRouter`; a
  `replicas` value greater than 1 renders `hostnamePrefix` instead of
  `hostname` (HA Connectors require a prefix, not a fixed hostname).
- `proxyClasses` is a map, one `ProxyClass` per key. Each key gets its own
  `app` pod label, so `topologySpreadConstraints` and the sibling PDB's
  selector only ever target that ProxyClass's own pods.
- `oidcDiscovery.enabled` toggles the `ClusterRoleBinding` in
  `oidc-discovery-rbac.yaml`. Its name is scoped to the release
  (`{{ .Release.Name }}-tailscale-operator-oidc-discovery`) so installing
  this chart into more than one cluster/namespace doesn't collide on a
  single hardcoded binding name.

Run `helm unittest charts/tailscale-operator` to exercise this branching
logic (see `tests/`).
