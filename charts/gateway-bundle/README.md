# gateway-bundle

This chart provisions [Gateway API](https://gateway-api.sigs.k8s.io/)
`Gateway` resources for shared use across the cluster. It is the companion
to the sibling [`gatewayapi`](../gatewayapi) chart, which owns the
`HTTPRoute` and `HealthCheckPolicy` resources that bind to these Gateways
via `parentRefs`.

## Upgrading to 3.0.0

Templates and values are unchanged from `2.3.0`. This version publishes to
`oci://us-docker.pkg.dev/artifact-storage-5748/helm-charts`.
`https://dave-inc.github.io/charts` is a frozen archive and will not get
`3.0.0`.

## Usage

The following is an example of how to define a Gateway with a single HTTPS
listener using the `gateway-bundle` chart:

```yaml
enabled: true
gateways:
  items:
    - name: default
      spec:
        listeners:
          - hostname: example-service.trydave.com
```

Most of the time, that will be all you need to do. The defaults in place
take care of the most common use cases.

Resources are named using the pattern `{item.name}` — the Gateway item's
`name` is used verbatim, with no release-name prefix. This is intentional so
that other charts (notably `gatewayapi`) can reference stable Gateway names
like `default` via `parentRefs`.

## How it works

The chart renders one `Gateway` resource per entry in `gateways.items`.
`metadata.annotations` and the default listener configuration both come from
`gateways.default`, so individual items can stay terse.

When an item's `rawSpec` is unset or `false` (the common case), each listener
is merged with the chart defaults:

- `port`, `protocol`, and `allowedRoutes` fall back to
  `gateways.default.spec.listener`.
- `name` is auto-derived from the hostname and protocol (e.g.
  `example-service-trydave-com-https`).
- For HTTPS listeners that don't declare a `tls` block, the chart
  auto-generates `tls.certificateRefs`. Wildcard listeners (`*.<domain>`)
  get a dedicated `wildcard-{domain}-{item-name}-tls` Secret (see
  [Wildcard domains](#wildcard-domains)). Otherwise the Secret name comes
  from the matching `tlsSecretGroups` entry (see below) —
  `{parentDomain}-{item-name}-tls`. Listeners whose hostname doesn't match
  any group fall back to `{hostname}-{item-name}-tls`. In all cases dots
  are replaced with dashes and the name is truncated to 63 characters.
  Pair this with cert-manager via the `cert-manager.io/cluster-issuer`
  annotation on `gateways.default.metadata` (the default annotation on a
  clean install is `letsencrypt`).

### Sharing TLS Secrets across listeners

GKE caps each `TargetHttpsProxy` (one per `Gateway`) at **15 SSL
certificates**. Since the per-listener Secret naming above produces one cert
per listener, a Gateway with more than 15 HTTPS listeners will fail to
reconcile with an error like:

```
At most 15 SSL certificate(s) (N in the request) can be specified for
TargetHttpsProxy patch.
```

`gateways.default.ext.tlsSecretGroups` (enabled by default — see
[values.yaml](./values.yaml)) collapses listeners onto shared Secrets by
parent domain:

```yaml
gateways:
  default:
    ext:
      tlsSecretGroups:
        enabled: true
        items:
          - parentDomain: trydave.com
          - parentDomain: daveapi.com
          - parentDomain: daveapi.io
```

A listener whose hostname equals `<parentDomain>` or is a subdomain of it
(`<sub>.<parentDomain>`) uses a Secret named `<parentDomain>-<gatewayName>-tls`
(dots replaced with dashes, truncated to 63 chars) instead of the per-listener
name. With the `cert-manager.io/cluster-issuer` annotation in place,
cert-manager's gateway-shim issues a single multi-SAN `Certificate` per shared
Secret — collapsing N listeners onto 1 cert slot on the underlying proxy.

Precedence: an explicit per-listener `tls` block wins; then wildcard listeners
(see [Wildcard domains](#wildcard-domains)); then the first matching group;
otherwise the per-listener fallback name applies. Set `enabled: false` to keep
per-listener Secret names everywhere.

If you need a Secret name the generator can't produce (e.g. a pre-existing
Secret that doesn't follow the `<parentDomain>-<gatewayName>-tls` pattern),
declare the listener's `tls` block inline — the explicit block always wins
over the auto-generated name.

You will notice there is no mention of `HTTPRoute` or `HealthCheckPolicy`
above. That's because routes and health checks are managed elsewhere — see
the [`gatewayapi`](../gatewayapi) helm chart.

### Wildcard domains

A listener can use a wildcard hostname to terminate TLS for every subdomain
under a domain with a single wildcard certificate:

```yaml
gateways:
  items:
    - name: default
      spec:
        listeners:
          # Quote the hostname — an unquoted `*` starts a YAML alias.
          - hostname: "*.trydave.com"
```

Wildcard listeners are detected automatically (any hostname starting with
`*.`) and get a dedicated Secret named `wildcard-<domain>-<gatewayName>-tls`,
where `<domain>` is the hostname with the leading `*.` stripped and dots
replaced with dashes (truncated to 63 chars). For example, `*.trydave.com` on
Gateway `default-private` yields `wildcard-trydave-com-default-private-tls`.

This takes precedence over `tlsSecretGroups`: a wildcard cert already covers
every subdomain, so it gets its own Secret rather than joining a parent-domain
multi-SAN group. Wildcard and concrete listeners can coexist on the same
Gateway — see [wildcard.yaml](./examples/wildcard.yaml).

### Custom addresses

Set `spec.addresses` on an item to bind the Gateway to a caller-specified
IP, hostname, or implementation-named address (e.g. a pre-reserved GCP
static IP):

```yaml
gateways:
  items:
    - name: default
      spec:
        addresses:
          - type: IPAddress
            value: 127.0.0.1
          - type: NamedAddress
            value: my-reserved-gcp-static-ip
        listeners:
          - hostname: example-service.trydave.com
```

`type` is one of `IPAddress`, `Hostname`, or `NamedAddress`. This works
without `rawSpec: true`, so listener defaults and `tlsSecretGroups` still
apply. For implementation-specific `<group>/<type>` values, drop into
`rawSpec: true`.

### GCPGatewayPolicy (SSL policy)

Set `gateways.default.ext.gcpGatewayPolicy.enabled: true` to attach a GKE
[`GCPGatewayPolicy`](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources#configure_ssl_policies)
to every rendered Gateway (disabled by default):

```yaml
gateways:
  default:
    ext:
      gcpGatewayPolicy:
        enabled: true
        metadata:
          annotations:
            argocd.argoproj.io/sync-wave: "2"
        spec:
          default:
            sslPolicy: min-tls-12
```

The chart renders one `GCPGatewayPolicy` per enabled item, named after the
Gateway (`{item.name}`), with `targetRef` pointing at it. This includes
`rawSpec: true` items. `spec.default` is copied verbatim and accepts
`sslPolicy`, `allowGlobalAccess`, and `region` (the latter two only apply to
internal Gateways such as `gke-l7-rilb`). `sslPolicy` must name an existing
Compute Engine SSL policy in the cluster's project.

`metadata.annotations` is copied onto each policy. It is separate from
`gateways.default.metadata.annotations`, which only applies to Gateways. The
chart default sets `argocd.argoproj.io/sync-wave: "2"` on policies (and
`"1"` on Gateways) so Argo CD applies each policy after the Gateway it
targets.

Individual Gateways can override this through their own
`ext.gcpGatewayPolicy`. `enabled` opts that Gateway in or out regardless of
the default, and its `spec.default` and `metadata.annotations` keys are
merged over the default's (item keys win):

```yaml
gateways:
  items:
    - name: default
      ext:
        gcpGatewayPolicy:
          spec:
            default:
              sslPolicy: min-tls-13   # only this Gateway
      spec:
        listeners:
          - hostname: example-service.trydave.com
    - name: internal
      ext:
        gcpGatewayPolicy:
          enabled: false             # no policy for this Gateway
      spec:
        listeners:
          - hostname: internal.trydave.com
```

An item can also opt in while the default is disabled; rendering fails if
the merged `spec.default` ends up empty.

### Full spec control

By default, each item's spec is merged with the chart defaults. Set
`rawSpec: true` to bypass merging and take full control of the spec:

```yaml
gateways:
  items:
    - name: extra-gw-0
      rawSpec: true
      spec:
        # Entire spec is yours — no defaults applied, including the listener
        # `name` field.
        ...
```

`metadata.annotations` is still inherited from `gateways.default` in this
mode; only `spec` is rendered verbatim.

## Further configuration

For a full list of configuration options, refer to the
[values.yaml](./values.yaml) file and the [examples](./examples) directory.

The examples cover:

| File | What it demonstrates |
|------|----------------------|
| [simple.yaml](./examples/simple.yaml) | Minimal single-Gateway with one HTTPS listener |
| [multi-hostname.yaml](./examples/multi-hostname.yaml) | One Gateway hosting several HTTPS hostnames |
| [per-listener-overrides.yaml](./examples/per-listener-overrides.yaml) | HTTP, Same-namespace, and caller-managed-TLS listeners on one Gateway |
| [shared-tls-secrets.yaml](./examples/shared-tls-secrets.yaml) | Many listeners sharing TLS Secrets by parent domain (stays under GKE's 15-cert limit) |
| [wildcard.yaml](./examples/wildcard.yaml) | Wildcard listener (`*.<domain>`) with a dedicated `wildcard-<domain>-<gatewayName>-tls` Secret, alongside concrete subdomains |
| [custom-addresses.yaml](./examples/custom-addresses.yaml) | Bind a Gateway to a specific IP or named address via `spec.addresses` |
| [gcp-gateway-policy.yaml](./examples/gcp-gateway-policy.yaml) | Attach a `GCPGatewayPolicy` (e.g. SSL policy) to every Gateway, with per-gateway overrides and opt-out |
| [raw-spec.yaml](./examples/raw-spec.yaml) | `rawSpec: true` escape hatch for full Gateway-spec control |

You can also apply `additionalLabels` to have extra labels added to all
resources created by the chart:

```yaml
additionalLabels:
  team: platform
  env: production
```

> **Schema:** `values.schema.json` is auto-generated from files in `schemas/`.
> Do not edit it directly — run `make schema-bundle` to regenerate it after
> schema changes.
