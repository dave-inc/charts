# common

The shared application chart. It renders the Deployment, Service, HPA and, when canary
is enabled, the canary and reverse proxy tiers that sit alongside them.

Configuration reference lives in [values.yaml](./values.yaml), which is commented in
place. This file covers only what changes between versions and what you have to do about
it.

## Upgrading to 0.11.1

This release changes shutdown and rollout timing for services, so a Pod that previously
terminated in about thirty seconds now takes up to a minute, and rollouts are deliberately
slower. Nothing needs to be set to adopt it: bumping the dependency version is enough, and
the sections below exist for the cases where the defaults do not suit a particular service.

The timing now lives at two levels. `serviceGracefulRollout` holds the values for a release
that is actually in a traffic path, and the top-level `.Values.*` fields are the fallback for
everything else. A workload with no Service — a pubsub consumer, a task handler — keeps its
old behaviour.

| Value | Before | Top level | `serviceGracefulRollout` |
|---|---|---|---|
| `terminationGracePeriodSeconds` | `31` | `31` | `60` |
| `minReadySeconds` | `0` | `0` | `60` |
| `preStopSleepSeconds` | did not exist | `0` | `20` |
| `autoscaling.minReplicas` | `1` | `null`, computed as 2 with canary enabled and 1 without | — |
| `kubeVersion` | `>=1.27.0-0` | `>=1.30.0-0` | — |

### Your cluster must be on 1.30 or newer

The application containers now drain using the native `preStop` sleep action, which is
enabled by default from 1.30 and stable from 1.34. Below 1.30 the API server prunes the
field and the container gets no drain at all, so the chart refuses to install instead.
Helm reports this at install time as a `chart requires kubeVersion` error.

### The new timing arrives through `serviceGracefulRollout`

`serviceGracefulRollout` carries `minReadySeconds`, `preStopSleepSeconds` and
`terminationGracePeriodSeconds` for a release that is in a traffic path, shadowing the
top-level defaults that everything else uses. It applies only when both `service.enabled` and
`serviceGracefulRollout.enabled` are true, and both default to true.

```yaml
serviceGracefulRollout:
  enabled: true
  minReadySeconds: 60
  preStopSleepSeconds: 20
  terminationGracePeriodSeconds: 60
```

So a service picks up the new timing with no configuration, while a workload with no Service
falls back to the top level and is unaffected. That split is the point of the block: the two
kinds of workload no longer share one default, and a service can be timed against the load
balancer in front of it without slowing down everything else.

The precedence, most specific first, is:

1. `canary.reverseProxy.*` — the per-tier override for the proxy only
2. `serviceGracefulRollout.*` — when `service.enabled` and its own `enabled` are true
3. top-level `.Values.*` — the default for everything else

The block feeds the control and canary Deployments, the reverse proxy's base timing, and the
Cloud SQL proxy's derived wait, so all of them move together. Override a single field to keep
the rest, or set `serviceGracefulRollout.enabled: false` to put a service back on the
top-level defaults entirely.

### Services now stay in the traffic path before shutting down

`serviceGracefulRollout.preStopSleepSeconds` renders a `preStop` sleep on the control and
canary application containers. It exists because a Pod keeps receiving requests after
termination begins: removal from a Google load balancer lags the Pod being killed, measured at
around twelve seconds in staging. `terminationGracePeriodSeconds` cannot do this on its own,
since it caps how long shutdown may take rather than holding the Pod open.

The two values are related and validated together. A `preStop` sleep that is greater than or
equal to the grace period fails the render rather than letting a Pod be SIGKILLed part-way
through draining.

Set `serviceGracefulRollout.preStopSleepSeconds: 0` to opt out — the top-level
`preStopSleepSeconds` is already `0` and is not the field to change here. Note that
`terminationGracePeriodSeconds: 0` is **not** an opt out at either level: it means a grace
period of literally zero seconds and an immediate SIGKILL, and it does not fall back to the
Kubernetes default of 30.

A service that already defines `deploymentContainer.lifecycle` keeps its own hook, which then
owns the whole drain and is not checked against the grace period.

### Rollouts wait a minute per wave

`serviceGracefulRollout.minReadySeconds: 60` requires a new Pod to stay Ready for a minute
before it counts as Available and the rollout retires an old one. It covers the gap between a
Pod being Ready and the data plane knowing about it, which is worst behind container-native
load balancing: GKE marks the `load-balancer-neg-ready` gate True before the NEG is attached
to a health-checked backend service, and Google recommends 60 or higher there.

With the default 25% surge and unavailable, a rollout moves in roughly four waves whatever the
replica count, so expect about four minutes of added rollout time, largely independent of how
large the service is. Plan for it in an emergency rollback, which is where it is felt most.

Set `serviceGracefulRollout.minReadySeconds: 0` to opt out.

The top-level `minReadySeconds` stays `0`, so nothing without a Service is slowed down. It is
still worth setting there for a different reason: the delay also gives a bad revision time to
fail before it reaches every replica, which applies to a pubsub consumer or task handler just
as much as to anything serving traffic. That is a deliberate per-service choice rather than a
default.

### Canary-enabled services get a replica floor of 2

`autoscaling.minReplicas` is now unset rather than `1`, which lets the chart tell a
deliberate value from an inherited one. With canary enabled it computes 2, because canary
puts a second Deployment in the traffic path and a tier at one Pod has no headroom while
that Pod is replaced. Without canary it stays 1, so single-Pod services are unaffected.

Setting `autoscaling.minReplicas` explicitly always wins, including setting it back to
`1`. The default is capped at `maxReplicas`, so a deliberately pinned single-replica
service still renders a valid HPA.

The reverse proxy keeps a floor of 2 of its own, since it is the tier fronted by the NEG
and one replica means one endpoint. Override it with
`canary.reverseProxy.autoscaling.minReplicas`.

### The reverse proxy can be tuned separately

The proxy inherits `minReadySeconds`, `terminationGracePeriodSeconds` and
`preStopSleepSeconds` from the effective value described above —
`serviceGracefulRollout` when it applies, otherwise the top level. Each also has
a `canary.reverseProxy.*` counterpart that wins outright, for when the proxy needs
different timing from the application it fronts, which is common: the proxy is the tier the
load balancer actually detaches from, so it often wants the longer drain.

### The Cloud SQL proxy now tracks the grace period

If `cloudsqlProxy.enabled` is set, the sidecar's `preStop` hook no longer waits for a
hardcoded 30 seconds. It waits the effective `terminationGracePeriodSeconds` minus one —
the `serviceGracefulRollout` value when that applies, otherwise the top level — so a service
sleeps 59 seconds rather than 30, while a workload with no Service derives 30 from the
top-level 31 and is unchanged.

This keeps a pairing that already existed but was easy to miss. The application reaches
its database through the proxy, so the proxy has to outlive the application's entire
shutdown, not just its `preStop` sleep. The old literal 30 was really the old default
grace period of 31 minus one; raising the grace period to 60 without changing it would
have left the application draining for its last 30 seconds with no database. Deriving the
value keeps the two aligned whatever the grace period is set to, and it fixes services
that already pin a longer grace period, which have been exposed to a smaller version of
this gap all along.

The visible cost is that deleting a service's Pod now takes about a minute rather than about
thirty seconds, since a Pod is not gone until every container exits. Pods evict in parallel, so a
node drain takes roughly that long in total rather than per Pod.

Setting `cloudsqlProxy.lifecycle` overrides the hook and makes its timing your
responsibility. The longer-term fix is running the proxy as a native sidecar, which
Kubernetes terminates only after the main containers exit, removing the need to coordinate
two timers at all.
