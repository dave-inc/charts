# gatewayapi

This chart is mean to replace the `ingress` entry in the `common` chart.
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

All the services need to have a `HealthCheckPolicy` defined, otherwise the
undelyling load balancer will mark the service as unhealthy and stop routing
traffic to it. For the request path, it's recommended to use the same endpoint
as the readiness probe of the service.

You will notice there is no mention of `Gateway` resource in the example above.
That's because the `Gateway` resource is managed elsewhere. TLS termination
is also handled where the `Gateway` resource is defined.

The `Gateway` helm chart is found [here](../gateway-bundle).

## Further configuration

For a full list of configuration options, please refer to the
[examples](./examples) directory and  [values.yaml](./values.yaml) file in
this chart. There you will find all the available options and their default
values, along with comments explaining what each option does.
