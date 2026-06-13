# gateway-bundle helm chart examples

This directory contains example configurations for the `gateway-bundle`
chart. These examples demonstrate how to provision Gateway resources, share
defaults across listeners, override individual fields, and drop into a
fully-controlled `rawSpec` mode when the chart's templated shape isn't
expressive enough.

- [simple](./simple.yaml): The minimum viable configuration. One Gateway
  with a single HTTPS listener; everything else (port, protocol,
  `allowedRoutes`, TLS cert ref) is filled in by chart defaults.
- [multi-hostname](./multi-hostname.yaml): One Gateway hosting several
  HTTPS listeners, all sharing the chart's listener defaults. Each
  hostname gets its own auto-generated TLS Secret reference.
- [per-listener-overrides](./per-listener-overrides.yaml): A single Gateway
  whose listeners selectively override port, protocol, `allowedRoutes`,
  and TLS. Useful as a reference for any non-default listener configuration
  without leaving the chart's templated mode.
- [shared-tls-secrets](./shared-tls-secrets.yaml): Many HTTPS listeners
  sharing TLS Secrets by parent domain via
  `gateways.default.ext.tlsSecretGroups`. Collapses N per-listener certs
  into one multi-SAN cert per shared Secret (via cert-manager's
  gateway-shim) so the Gateway stays under GKE's 15-SSL-certificate cap
  on the underlying `TargetHttpsProxy`.
- [raw-spec](./raw-spec.yaml): An escape hatch that sets `rawSpec: true`
  and supplies the entire Gateway spec verbatim. Use this when the chart's
  templated mode can't express what you need; metadata is still inherited
  from `gateways.default`.

You can mix and match these configurations to provision more sophisticated
Gateway topologies as needed. Each example is self-contained and can be
rendered using `helm template shared-gateways . -f examples/simple.yaml` at
the base of the `gateway-bundle` chart directory, replacing `simple.yaml`
with the desired example file.
