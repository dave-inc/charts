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
like `shared-gw-0` via `parentRefs`.

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
