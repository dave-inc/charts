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
```

Most of the time, that will be all you need to do. The defaults in place take
care of the most common use cases.

Resources are named using the pattern `{Release.Name}-{item.name}`.

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

The chart will automatically create both `HTTPRoute` and `HealthCheckPolicy`
resources for the service.

`HTTPRoute` will be able to handle the traffic prefixed by "/" (i.e, all
traffic) for the specified hostnames and route it to the service.

All services need to have a `HealthCheckPolicy` defined, otherwise the
underlying load balancer will mark the service as unhealthy and stop routing
traffic to it. For the request path, it's recommended to use the same endpoint
as the readiness probe of the service. Note that `HealthCheckPolicy` is a
GKE-specific CRD (`networking.gke.io/v1`) and is not part of the standard
Gateway API.

You will notice there is no mention of `Gateway` resource in the example above.
That's because the `Gateway` resource is managed elsewhere. TLS termination
is also handled where the `Gateway` resource is defined.

The `Gateway` helm chart is found [here](../gateway-bundle).

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

## Further configuration

For a full list of configuration options, refer to the
[values.yaml](./values.yaml) file and the [examples](./examples) directory.

The examples cover:

| File | What it demonstrates |
|------|----------------------|
| [simple.yaml](./examples/simple.yaml) | Minimal route + health check |
| [timeouts.yaml](./examples/timeouts.yaml) | Per-request and per-backend timeouts |
| [redirect.yaml](./examples/redirect.yaml) | HTTP redirect with no backend |
| [custom-path-match.yaml](./examples/custom-path-match.yaml) | PathPrefix routing to a non-root path |

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
