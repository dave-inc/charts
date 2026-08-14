# common

The shared application chart. It renders the Deployment, Service and HPA, and, when
canary is enabled, a Rollout (Argo Rollouts) that references the Deployment via
`workloadRef` instead of duplicating it.

Configuration reference lives in [values.yaml](./values.yaml), which is commented in
place. This file covers only what changes between versions and what you have to do about
it.

## Upgrading to 0.11.1

This release changes shutdown and rollout defaults for every service, so a Pod that
previously terminated in about thirty seconds now takes up to a minute, and rollouts are
deliberately slower. Nothing needs to be set to adopt it: bumping the dependency version
is enough, and the sections below exist for the cases where the defaults do not suit a
particular service.

| Value | Before | After |
|---|---|---|
| `terminationGracePeriodSeconds` | `31` | `60` |
| `minReadySeconds` | `0` | `60` |
| `preStopSleepSeconds` | did not exist | `20` |
| `autoscaling.minReplicas` | `1` | `null`, computed as 2 with canary enabled and 1 without |
| `kubeVersion` | `>=1.27.0-0` | `>=1.30.0-0` |

### Your cluster must be on 1.30 or newer

The application containers now drain using the native `preStop` sleep action, which is
enabled by default from 1.30 and stable from 1.34. Below 1.30 the API server prunes the
field and the container gets no drain at all, so the chart refuses to install instead.
Helm reports this at install time as a `chart requires kubeVersion` error.

### Pods now stay in the traffic path before shutting down

`preStopSleepSeconds` renders a `preStop` sleep on the application container. It exists
because a Pod keeps receiving requests after termination begins:
removal from a Google load balancer lags the Pod being killed, measured at around twelve
seconds in staging. `terminationGracePeriodSeconds` cannot do this on its own, since it
caps how long shutdown may take rather than holding the Pod open.

The two values are related and validated together. A `preStop` sleep that is greater than
or equal to the grace period fails the render rather than letting a Pod be SIGKILLed
part-way through draining.

Set `preStopSleepSeconds: 0` to opt out. Note that `terminationGracePeriodSeconds: 0` is
**not** an opt out: it means a grace period of literally zero seconds and an immediate
SIGKILL, and it does not fall back to the Kubernetes default of 30.

A service that already defines `deploymentContainer.lifecycle` keeps its own hook, which
then owns the whole drain and is not checked against the grace period.

### Rollouts wait a minute per wave

`minReadySeconds: 60` requires a new Pod to stay Ready for a minute before it counts as
Available and the rollout retires an old one. It covers the gap between a Pod being Ready
and the data plane knowing about it, which is worst behind container-native load
balancing, and it also gives a bad revision time to fail before it reaches every replica.
That second reason applies to workloads with no endpoints at all, which is why it is not
limited to services behind a load balancer.

With the default 25% surge and unavailable, a rollout moves in roughly four waves whatever
the replica count, so expect about four minutes of added rollout time, largely independent
of how large the service is. Plan for it in an emergency rollback, which is where it is
felt most.

Set `minReadySeconds: 0` to opt out.

### Canary-enabled services get a replica floor of 2

`autoscaling.minReplicas` is now unset rather than `1`, which lets the chart tell a
deliberate value from an inherited one. With canary enabled it computes 2, because canary
puts a second ReplicaSet in the traffic path during a rollout and a tier at one Pod has no
headroom while that Pod is replaced. Without canary it stays 1, so single-Pod services are
unaffected.

Setting `autoscaling.minReplicas` explicitly always wins, including setting it back to
`1`. The default is capped at `maxReplicas`, so a deliberately pinned single-replica
service still renders a valid HPA.

### The Cloud SQL proxy now tracks the grace period

If `cloudsqlProxy.enabled` is set, the sidecar's `preStop` hook no longer waits for a
hardcoded 30 seconds. It waits `terminationGracePeriodSeconds` minus one, so with the new
default it sleeps 59 seconds rather than 30.

This keeps a pairing that already existed but was easy to miss. The application reaches
its database through the proxy, so the proxy has to outlive the application's entire
shutdown, not just its `preStop` sleep. The old literal 30 was really the old default
grace period of 31 minus one; raising the grace period to 60 without changing it would
have left the application draining for its last 30 seconds with no database. Deriving the
value keeps the two aligned whatever the grace period is set to, and it fixes services
that already pin a longer grace period, which have been exposed to a smaller version of
this gap all along.

The visible cost is that Pod deletion now takes about a minute rather than about thirty
seconds, since a Pod is not gone until every container exits. Pods evict in parallel, so a
node drain takes roughly that long in total rather than per Pod.

Setting `cloudsqlProxy.lifecycle` overrides the hook and makes its timing your
responsibility. The longer-term fix is running the proxy as a native sidecar, which
Kubernetes terminates only after the main containers exit, removing the need to coordinate
two timers at all.
