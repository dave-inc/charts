# gatewayapi helm chart examples

This directory contains example configurations for the `gatewayapi` chart.
These examples demonstrate how to use it to route traffic to backend
services, perform redirects, configure timeouts, and implement health check
and backend policies.

- [simple](./simple.yaml): A minimal example that routes traffic to a backend
  service and configures an HTTP health check policy. Also shows how to attach
  custom annotations to the rendered resources via `metadata.annotations`.
- [redirect](./redirect.yaml): An example that issues a 301 redirect from one
  hostname to another. Health check policy is disabled since no backend is
  configured.
- [custom-path-match](./custom-path-match.yaml): An example that restricts
  routing to requests matching a path prefix, with an HTTP health check policy.
- [timeouts](./timeouts.yaml): An example that configures per-request and
  per-backend-attempt timeouts, with an HTTP health check policy.
- [gcpbackendpolicies](./gcpbackendpolicies.yaml): An example that attaches a
  GCPBackendPolicy to a backend Service to configure backend-service settings
  (here, the response timeout), alongside an HTTP health check policy.

You can mix and match these configurations to create more complex routing
rules and policies as needed. Each example is self-contained and can be
rendered using `helm template example-service . -f examples/simple.yaml` at
the base of the `gatewayapi` chart directory, replacing `simple.yaml` with
the desired example file.
