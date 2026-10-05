# Migrating a service onto Argo Rollouts canary

Steps and ordering guarantees for moving a service onto this chart's Argo
Rollouts canary setup (and, if applicable, off an older reverse-proxy/canary-
Deployment architecture) without downtime, plus the canary-specific behavior
that keeps applying once it's running. See [values.yaml](./values.yaml) for
the configuration reference and [README.md](./README.md) for everything else
about this chart.

## Opting a single deployment out of canary

`global.canary.enabled` is a single toggle at the umbrella-chart level, driving every
service deployed alongside it into canary together. Set this chart's own
`canary.enabled: false` to opt one service out regardless of that toggle: it always
renders a plain Deployment with a static `replicaCount`, never a Rollout, and no
canary/stable Services. Use this for a service pinned to an exact replica count by an
invariant a transient extra canary Pod would violate. There is no matching override in
the other direction — enabling canary here alone still leaves the `gatewayapi` chart's
backendRef expansion off, so the Rollout would have no traffic split to plug into.

## Argo CD order for canary rollouts

Every Service this chart creates — the plain `Service` (`service.yaml`, which doubles as
`stableService` once canary is enabled), the Cloud Armor `Service` (`service-cloudarmor.yaml`),
and, when canary is enabled, the canary Service (`service-canary.yaml`) — applies in sync
wave `"-1"`, ahead of everything else. That protects a service migrating off a now-removed tier (its
Deployment, Service, etc. pruned in the same sync, as happened when this chart moved off a
separate reverse-proxy/canary-Deployment architecture onto Argo Rollouts): the Service's
selector change needs to reach the API server, and the load balancer or kube-proxy needs to
start discovering the new endpoints, before that prune happens. Without an explicit wave, a
Service defaults to `"0"` — the same wave as an unannotated pruned resource — with no
ordering between the two. Set `service.annotations["argocd.argoproj.io/sync-wave"]` to
override the plain Service's wave; the others don't expose an override today.

After that, the Gateway API chart applies its `HTTPRoute` in wave `"2"` (needing both
Rollouts-managed Services to already exist, which wave `"-1"` guarantees). The Rollout is
in wave `"3"`, allowing its Gateway API traffic-routing plugin to update the existing route,
and an HPA, VPA, or KEDA `ScaledObject` targeting that Rollout is in wave `"4"`. The
referenced Deployment remains in the default wave `"0"`.

This breaks the resource cycle as one direction: Services → HTTPRoute → Rollout →
autoscaler. If a canary HTTPRoute overrides its default sync-wave, keep it below the
Rollout's wave or override the Rollout and autoscaler waves together.

A sync-wave only orders when Argo CD *applies* each resource — it does not wait for the
load balancer's health checks or NEG registration to actually converge, and it can't make a
tier's own removal (e.g. deleting a reverse proxy that was the sole thing routing traffic
for both internal and external callers) atomic with the new path taking over. Treat the
wave ordering here as reducing, not eliminating, the risk of a one-time migration like that;
watch the real traffic/health signals live during it, or stage it as two changes, rather
than relying on the chart alone.

### Old infra being removed needs `PruneLast`, not a sync-wave

Sync-wave only controls resources this chart still renders. A tier being *removed* — like
the reverse-proxy/canary-Deployment architecture this chart moved off of onto Argo Rollouts —
has no manifest for Argo CD to read a wave from once it drops out of the chart, so it prunes
using whatever wave was last live on it. A resource that was never annotated (true of every
one of those old reverse-proxy/canary-Deployment resources) defaults to wave `"0"`, which
lands *before* the HTTPRoute (`"2"`), Rollout (`"3"`), and autoscaler (`"4"`) above ever
reconcile — the old infra would be torn down before the new path is even up, not after.

There is no chart-side fix for this: stamping a later wave onto a resource that is being
deleted in the same release that removes it doesn't work, because Argo CD would need that
wave to already be live on the object, from a prior sync, before the resource disappears from
the manifest.

The fix is the Application's own `syncPolicy`, not this chart:

```yaml
syncPolicy:
  syncOptions:
    - PruneLast=true
```

`PruneLast=true` defers every prune in the sync to an implicit final wave, run only after
every other wave has applied *and gone healthy* — old infra last, exactly as intended, with
no dependency on a wave ever having been set on it before. Set this on the Application (or
ApplicationSet template) for any service upgrading through this migration; this chart cannot
set it for you, since the Application resource lives outside this repo.

Two things to know before relying on it:

- It's an Application-wide setting, not scoped to this one migration — it defers *every*
  future prune on that Application the same way, which is normally what you want anyway.
- If any wave never goes healthy (a stuck Rollout, a misconfigured HPA), the prune never
  runs. Old and new infra both stay live, at double the cost, until someone intervenes — the
  safe failure mode, but worth knowing about operationally rather than being surprised by it.

### Turning on canary for an autoscaled service needs `canary.initialReplicas` too

A Rollout's first-ever revision always promotes immediately: there is no prior stable
revision to canary against, so Argo Rollouts skips canary steps entirely and marks itself
healthy as soon as its *current* `replicas` count is Ready — then `canary.scaleDown`
(`onsuccess` by default) retires the old Deployment's real capacity in that same instant.

That current count is a problem specifically when `autoscaling.enabled` (or
`kedaScaling.enabled`) is also true. This chart omits `replicas` on the Rollout in that case,
deferring to the HPA/`ScaledObject` — correct for steady state, but on a brand-new Rollout
object, an omitted `replicas` is Kubernetes' own implicit default of `1`, not this service's
real steady-state size, until the HPA's own reconcile loop catches up and patches it. The
Rollout can promote — and the old Deployment's pods can be torn down — while the new
ReplicaSet still has only one pod. This isn't theoretical: it's the confirmed root cause of a
live incident, including a recurrence on a routine post-migration update (not just the
original cutover), traced directly through Argo Rollouts' and Argo CD's own source — both
treat a missing `spec.replicas` as `1` when deciding whether the Rollout is healthy.

`canary.initialReplicas` fixes this, and it's deliberately more than just a replica-count
override: **setting it is on its own enough to turn canary on for this service**, independent
of `global.canary.enabled`. There's no legitimate reason to ever set this value except to
stage a migration onto canary ahead of the real cutover, so the chart treats setting it as
that signal — there's no state where you'd want it set but the Rollout left off:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
canary:
  initialReplicas: 5  # whatever this service is actually running right now
```

With only this set — `global.canary.enabled` still untouched — the Rollout and its canary
Service are created at real capacity and start warming up for real (the plain Service, which
doubles as stable, already exists regardless):
GCP attaches their NEGs and runs its own health checks, all before any real traffic depends
on them. This is the piece sync-wave ordering alone can't provide, because a sync-wave only
orders *when Argo CD applies* a resource, not when the load balancer finishes converging on
it. The Rollout's `trafficRouting` stays off during this window — it still waits for the
real `global.canary.enabled`, specifically so it never tries to manage weights on a
`gatewayapi` HTTPRoute that hasn't expanded its backendRefs yet (see that chart's own
canary section for why that combination hard-errors every reconcile otherwise).

Migrating an autoscaled service onto canary is then two steps instead of one:

1. Set `canary.initialReplicas` to the service's actual current replica count. Wait,
   confirm fully promoted at that count and the Services' backends are healthy
   (`kubectl argo rollouts get rollout`, `gcloud compute backend-services get-health`).
2. Flip `global.canary.enabled: true`. This both completes the cutover on this chart's side
   (arms `trafficRouting`) and is the same flag the `gatewayapi` chart reads to expand its
   HTTPRoute — so the real traffic switch lands on backends that are already warm, not
   ones racing their own startup. Remove `canary.initialReplicas` in a follow-up commit
   once confirmed healthy, to hand replica count back to the HPA/`ScaledObject` for good.

## The Rollout needs its own `minReadySeconds`

`serviceGracefulRollout.minReadySeconds` (see [README.md](./README.md)'s "Rollouts wait a
minute per wave") applies equally to the Argo Rollouts `Rollout` (rollout.yaml) when canary
is enabled, but it needs its own line to do so: `workloadRef` only copies the referenced
Deployment's `.spec.template` (so `terminationGracePeriodSeconds` and the preStop hook
already carry over), not sibling `Rollout.spec` fields like `minReadySeconds`. Without it,
the Rollout's own canary/stable Pods would default to `minReadySeconds: 0` regardless of
what the Deployment is set to -- exactly the gap staging testing on `bei-test-service`
traced a run of 503s to: a Pod whose endpoint hadn't yet attached to (or detached from) its
NEG could count as Available the instant it passed readiness.

## Scale-down also waits for the NEG to catch up

`minReadySeconds` (above) covers the pod-attach side of the NEG/Envoy propagation lag — a
new Pod counting as Available before the load balancer actually knows about it. The same
lag exists symmetrically on teardown: an old Pod can be killed before the load balancer has
detached its endpoint, serving 503s out of a backend that no longer exists. The Rollout
covers that side with its own `scaleDownDelaySeconds`, set to `minReadySeconds + 10` rather
than an independent value — both delays exist for the same underlying lag, just on opposite
sides (attach vs. detach), so the teardown side only needs to outlast whatever the build-up
side was already tuned to, with no second number to keep in sync if `minReadySeconds` is
ever retuned. This isn't theoretical either: it's the confirmed root cause of 503s on
`service-template-test-service` when the old ReplicaSet scaled down immediately on
promotion.

Argo Rollouts only accepts `scaleDownDelaySeconds` when `trafficRouting` is actually
present — it hard-rejects the spec (`InvalidSpec`) otherwise. That matters here because the
`canary.initialReplicas` warm-up window above deliberately runs with `trafficRouting` still
off (`global.canary.enabled` not yet flipped), so this field has to be gated on the exact
same condition that decides whether `trafficRouting` renders, not just "is `minReadySeconds`
set" — confirmed live on `service-template-test-service`, where getting that gate wrong
degraded the Rollout during that exact window.

This value isn't independently configurable — there's no `canary.scaleDownDelaySeconds` to
set. The only lever is `minReadySeconds` itself (see above).

## Canary-enabled services get a replica floor of 2

`autoscaling.minReplicas` is unset rather than `1`, which lets the chart tell a deliberate
value from an inherited one. With canary enabled it computes 2, because canary puts a
second ReplicaSet in the traffic path during a rollout and a tier at one Pod has no headroom
while that Pod is replaced. Without canary it stays 1, so single-Pod services are
unaffected.

Setting `autoscaling.minReplicas` explicitly always wins, including setting it back to `1`.
The default is capped at `maxReplicas`, so a deliberately pinned single-replica service
still renders a valid HPA.
