# gatewayapi helm chart examples

This directory contains example configurations for the `gatewayapi` chart.
These examples demonstrate how to use it to route traffic to backend
services, perform redirects, configure timeouts, and implement health check
and backend policies.

## Supported features

- [simple](./simple.yaml): A minimal example that routes traffic to a backend
  service, configures an HTTP health check policy, and defines a
  GCPBackendPolicy resource with the default `timeoutSec` value. Also
  shows how to attach custom annotations to the rendered resources via
  `metadata.annotations`.
- [redirect](./redirect.yaml): An example that issues a 301 redirect from one
  hostname to another. Health check policy is disabled since no backend is
  configured.
- [custom-path-match](./custom-path-match.yaml): An example that restricts
  routing to requests matching a path prefix, with an HTTP health check policy.
- [gcpbackendpolicies](./gcpbackendpolicies.yaml): How to set a custom timeout
  and connection-draining timeout. An example that attaches a GCPBackendPolicy
  to a backend Service to configure backend-service settings (here, the response
  timeout and the connection-draining timeout), alongside an HTTP health check
  policy.
- [cloud-armor](./cloud-armor.yaml): How to attach a Google Cloud Armor
  security policy to a backend Service via `GCPBackendPolicy.spec.default.securityPolicy`.
  The policy must already exist in GCP; the chart only references it by name.
  Also documents the three states of the field -- omitted (leave untouched), a
  name (attach), and `""` (detach) -- and the regional-vs-global scope rule.
- [section-name](./section-name.yaml): An example that pins the route to a
  specific Gateway listener via `parentRefs[].sectionName`, alongside an HTTP
  health check policy and a GCPBackendPolicy.
- [canary](./canary.yaml): An example with two `backendRefs` (stable and
  canary) for use with the `common` chart's `canary.enabled` feature and Argo
  Rollouts' Gateway API traffic router plugin, which mutates the two
  backendRefs' `weight` fields as the rollout progresses.

You can mix and match these configurations to create more complex routing
rules and policies as needed. Each example is self-contained and can be
rendered using `helm template example-service . -f examples/simple.yaml` at
the base of the `gatewayapi` chart directory, replacing `simple.yaml` with
the desired example file.

## Unsupported features

There are some features already implemented in this helm chart that are not
yet supported by GKE's Gateway API offering. These include:

- [httprote-timeouts](./httproute-timeouts.yaml): Not supported by GKE's
  Gateway API offering yet. An example that configures per-request and
  per-backend-attempt timeouts, with an HTTP health check policy.

These features will become available once GKE's Gateway API implementation
supports them.
