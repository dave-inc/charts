# gateway-bundle

This chart provisions [Gateway API](https://gateway-api.sigs.k8s.io/)
`Gateway` resources for shared use across the cluster. It is the companion
to the sibling [`gatewayapi`](../gatewayapi) chart, which owns the
`HTTPRoute` and `HealthCheckPolicy` resources that bind to these Gateways
via `parentRefs`.

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
  auto-generates `tls.certificateRefs` with a Secret named
  `{hostname}-{item-name}-tls` (dots replaced with dashes, truncated to 63
  characters). Pair this with cert-manager via the
  `cert-manager.io/cluster-issuer` annotation on `gateways.default.metadata`
  (the default annotation on a clean install is `letsencrypt`).

### Sharing TLS Secrets across listeners

GKE caps each `TargetHttpsProxy` (one per `Gateway`) at **15 SSL
certificates**. Since the per-listener Secret naming above produces one cert
per listener, a Gateway with more than 15 HTTPS listeners will fail to
reconcile with an error like:

```
At most 15 SSL certificate(s) (N in the request) can be specified for
TargetHttpsProxy patch.
```

Set `gateways.default.ext.tlsSecretGroups` to collapse listeners onto shared
Secrets by parent domain:

```yaml
gateways:
  default:
    ext:
      tlsSecretGroups:
        - parentDomain: trydave.com
        - parentDomain: daveapi.com
        - parentDomain: daveapi.io
```

A listener whose hostname matches `<parentDomain>` or `*.<parentDomain>`
uses a secret named `<parentDomain>-<gatewayName>-tls` instead of the
per-listener name. The dots are replaced with dashes. With the
`cert-manager.io/cluster-issuer` annotation in place, cert-manager's
gateway-shim issues a single multi-SAN `Certificate` per shared Secret —
collapsing N listeners onto 1 cert slot on the underlying proxy.

Precedence: an explicit per-listener `tls` block wins; otherwise the first
matching group is used; otherwise the per-listener fallback name applies.

You will notice there is no mention of `HTTPRoute` or `HealthCheckPolicy`
above. That's because routes and health checks are managed elsewhere — see
the [`gatewayapi`](../gatewayapi) helm chart.

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
