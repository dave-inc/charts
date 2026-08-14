# gatewayapi

This chart is meant to replace the `ingress` entry in the `common` chart.
It uses [Gateway API](https://gateway-api.sigs.k8s.io/) resources to define
routing rules and health checks for services in the cluster.

## Usage

The following is an example of how to define a route and health check for a
service using the `gatewayapi` chart:

```yaml
enabled: true
routes:
  items:
    - name: example-service
      spec:
        hostnames:
          - example-service.trydave.com
        parentRefs:
          - name: default
        rules:
          - backendRefs:
              - name: example-service
                # Service port
                port: 80
healthCheckPolicies:
  items:
    - name: example-service
      spec:
        default:
          config:
            httpHealthCheck:
              # Container port
              port: 8080
              requestPath: /your-health-check-endpoint
        targetRef:
          name: example-service
gcpBackendPolicies:
  items:
    - name: example-service
      spec:
        targetRef:
          name: example-service
```

Most of the time, that will be all you need to do. The defaults in place take
care of the most common use cases.

Resources are named using the `name` field from each item (e.g. `example-service`).

Just for illustration purposes, here is how the same configuration would
look like if we were to use `ingress` instead of `gatewayapi`:

```yaml
enabled: true
hosts:
  - host: example-service.trydave.com
    name: example-service
    annotations:
      kubernetes.io/ingress.class: nginx
      kubernetes.io/tls-acme: "true"
      cert-manager.io/cluster-issuer: letsencrypt
    paths:
      - backend:
          service:
            name: example-service
            port:
              number: 80
        path: /
        pathType: ImplementationSpecific
tls:
  - secretName: example-service-trydave-com-tls
    hosts:
      - example-service.trydave.com
```

Both are functionally equivalent.

## How it works

The chart will create `HTTPRoute`, `HealthCheckPolicy` and `GCPBackendPolicy`
resources for the service.

By default `HTTPRoute` will be able to handle the traffic prefixed by "/"
(i.e, all traffic) for the specified hostnames and route it to the service.

All services need to have a `HealthCheckPolicy` defined, otherwise the
underlying load balancer will mark the service as unhealthy and stop routing
traffic to it. For the request path, it's recommended to use the same endpoint
as the readiness probe of the service unless some other endpoint is more
appropriate for your use case. Note that `HealthCheckPolicy` is a GKE-specific
CRD (`networking.gke.io/v1`) and is not part of the standard Gateway API.

The chart can also render `GCPBackendPolicy` resources (another GKE-specific
CRD, `networking.gke.io/v1`) to attach backend-service configuration such as
`timeoutSec` to a `Service`. Like health check policies, they reference the
target `Service` via `spec.targetRef.name`:

```yaml
gcpBackendPolicies:
  items:
    - name: example-service
      spec:
        default:
          timeoutSec: 60
        targetRef:
          name: example-service
```

if `spec.default.timeoutSec` is omitted, the default value of 60 seconds is
used.

You will notice there is no mention of `Gateway` resource in the example above.
That's because the `Gateway` resource is managed elsewhere. TLS termination
is also handled where the `Gateway` resource is defined.

The `Gateway` helm chart is found [here](../gateway-bundle).

### Sync ordering (Argo CD sync-wave)

Every `HTTPRoute`, `HealthCheckPolicy` and `GCPBackendPolicy` this chart renders
is annotated with `argocd.argoproj.io/sync-wave: "2"` by default. All three
attach to a `Service` (via `targetRef` / `backendRefs`). Ordinary `common` /
`cloudarmor` Services are in the implicit default wave `"0"`; the `common`
chart's canary and stable Services are in wave `"1"`. Defaulting these
resources to wave `"2"` still guarantees Argo CD reconciles every target
Service well before the route or policy, giving the Service's GCP-side
NEG/backend real wall-clock time to register so a route never reconciles ahead
of the backend it binds to (which would briefly mark that backend unhealthy
until the NEG catches up).

The default is overridable — per item via its `metadata.annotations` (setting
`argocd.argoproj.io/sync-wave` there wins over the chart default), and
chart-wide by changing `<resource>.default.metadata.annotations` in your values
(e.g. `routes.default.metadata.annotations`).

When canary is enabled, this `HTTPRoute` is also load-bearing for the Rollout's
own health: Argo Rollouts' Gateway API traffic-routing plugin (see
`charts/common/templates/rollout.yaml`) has to patch this route's weights for
the Rollout to ever go healthy. Rather than pull the route earlier (and give up
its buffer after the Services it targets), the `common` chart instead gives the
Rollout — and, since its `scaleTargetRef` follows it, the HPA/VPA/KEDA
`ScaledObject` — a later sync-wave than this route's default `"2"`, so the
dependency runs one direction only: Services → route → Rollout → autoscaler.
See `charts/common/templates/rollout.yaml` and `charts/common/README.md` for
the wave assignments on that side.

### Full spec control

By default, each item's spec is merged with the chart defaults. Set `rawSpec: true`
to bypass merging and take full control of the spec:

```yaml
routes:
  items:
    - name: example-service
      rawSpec: true
      spec:
        # Entire spec is yours — no defaults applied
        ...
```

### Canary rollouts via Argo Rollouts' Gateway API plugin

Turn on `canary.enabled` in the `common` chart for the same app, then add
`canary: true` to a single `backendRefs` entry here — no need to hand-type
either Service name:

```yaml
routes:
  items:
    - name: example-service
      spec:
        hostnames:
          - example-service.trydave.com
        parentRefs:
          - name: default
        rules:
          - backendRefs:
              - name: example-service
                port: 80
                canary: true
```

`canary: true` expands that single entry into a stable+canary backendRef
pair named `example-service-stable`/`example-service-canary` — the same
`"<name>-stable"/"<name>-canary"` convention the `common` chart always uses
for its canary/stable Services, as long as both charts are given the same
base app name. Initial weights default to all traffic on stable, none on
canary (override via `weight`/`canaryWeight` on the same entry if you need
something else).

Argo Rollouts' `argoproj-labs/gatewayAPI` traffic router plugin then mutates
these two backendRefs' `weight` fields in place as the rollout progresses
through its canary steps — the defaults above are only the starting point.
The route's `name` must match the `httpRoute` value configured under the
Rollout's `strategy.canary.trafficRouting.plugins["argoproj-labs/gatewayAPI"]`
(passed through as-is via the `common` chart's `canary.trafficRouting`).
See [examples/canary.yaml](./examples/canary.yaml) for a full example.

> **Note:** because the plugin mutates `weight` on the live resource outside
> of Helm/Argo CD, keep this route out of Argo CD's drift detection for that
> field (e.g. via `spec.ignoreDifferences` on the Argo CD `Application`) —
> otherwise the next sync will reset the weights and fight the rollout, the
> same way an un-excluded `replicas` field fights a Rollout-managed Deployment.

## Further configuration

This document only covers the most common use cases. For a full list of
configuration options, refer to the [values.yaml](./values.yaml) file and
the [examples](./examples) directory.

## Custom labels

You can also apply `additionalLabels` to have extra labels added to all
resources created by the chart:

```yaml
additionalLabels:
  team: platform
  env: production
```

This is the same pattern the `common` chart follows.

### Custom annotations

Individual routes and health check policies accept custom annotations via a
`metadata.annotations` block. Unlike `additionalLabels` (which is applied
chart-wide to every resource), these annotations are applied only to that
specific rendered resource:

```yaml
routes:
  items:
    - name: example-service
      metadata:
        annotations:
          networking.gke.io/some-annotation: "value"
      spec:
        ...
```

The same `metadata.annotations` key is supported on entries under
`healthCheckPolicies.items` and `gcpBackendPolicies.items`.

> **Schema:** `values.schema.json` is auto-generated from files in `schemas/`.
> Do not edit it directly — run `make schema-bundle` to regenerate it after
> schema changes.
