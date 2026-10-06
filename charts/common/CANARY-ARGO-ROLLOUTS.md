# Migrating a service onto Argo Rollouts canary

Steps and ordering guarantees for moving a service onto this chart's Argo
Rollouts canary setup (and, if applicable, off an older reverse-proxy/canary-
Deployment architecture) without downtime, plus the canary-specific behavior
that keeps applying once it's running. See [values.yaml](./values.yaml) for
the configuration reference and [README.md](./README.md) for everything else
about this chart.

## Moving a service off old-way (rproxy) canary onto Argo Rollouts canary with zero downtime

### The one rule everything below follows

Never let a single sync both **narrow** what a Service's selector matches and **delete**
the pods that narrowing would drop, in the same step. Every step below either only
*adds* to what's matched, or only removes something that's already redundant by the
time it's removed. That's the entire trick — no step is a genuine cutover, just a
sequence of additions and then cleanup of what's no longer needed.

### Prerequisites

- You only need this section if your service is on the existing canary-with-rproxy
  setup (`canary.enabled: true` + `reverseProxy` already live). If it isn't, skip
  straight to "Turning on canary for an autoscaled service needs `canary.initialReplicas`
  too" below.
- Know which tiers actually have live rproxy today (check for `canary.enabled: true`
  + `reverseProxy` in each workload's values file — not every tier necessarily has it).
- Know each autoscaled tier's real current replica count (`kubectl get deploy` or
  the `autoscaling.minReplicas`/`maxReplicas` in values, if they're pinned equal).

### Step 1 — bump chart version + `canary.migrate: true` (one PR)

For every tier with live rproxy, add `migrate: true` alongside its existing
`canary.enabled: true` block — don't remove anything yet. Combine this with the
chart version bump in the same PR; it's safe because the render is purely additive:
the Service's selector widens to the `application` label (shared by both the rproxy
pods and the app's own pods), so app pods join what's already being routed to.
Nothing is torn down. (The pre-existing `canary.enabled: true` left over from the
old-way config does nothing on this chart line by itself — see Step 2.)

Merge, then confirm: Argo app `Synced`/`Healthy`, rproxy pods still running, and the
Service's live selector now shows the wide `application` label (not the narrow
`app.kubernetes.io/name`/`instance` pair).

### Step 2 — delete the old canary block, warm up the Rollout, and flip traffic (one PR)

Once step 1 is confirmed healthy, do all three of these in the same PR — confirmed safe
to combine and verified working end-to-end in production:

1. Remove the whole `canary:` block (`enabled`, `migrate`, `reverseProxy`) from each
   tier that had rproxy. This is safe because:
   - `canary.enabled: true` left over does nothing on this chart line — only
     `global.canary.enabled` or `canary.initialReplicas` can turn on the new mechanism,
     and neither is set yet.
   - `reverseProxy.*` is only read by templates gated on `migrate`, which is now gone.

   This deletes rproxy/`-control` (now redundant — app pods already serve via the
   widened selector) and narrows the main Service's selector back to its normal,
   specific form.

2. For **every autoscaled tier** (not just the ones that had rproxy — any tier under
   the same chart that's autoscaled), add:

   ```yaml
   canary:
     initialReplicas: <current real replica count>
   ```

   This forces the Rollout + canary Service into existence, independent of
   `global.canary.enabled` — real capacity, NEGs attached, GCP health checks passing —
   with zero live traffic, since the actual weight-shifting stays off until the raw
   `global.canary.enabled` is also true. Get the replica count right: an omitted value
   defaults the Rollout's first reconcile to Kubernetes' implicit `1`, not the tier's
   real steady-state size, which is the confirmed root cause of a past live incident
   (see "Turning on canary for an autoscaled service needs `canary.initialReplicas` too"
   below).

3. Add `production/values.yaml` (or wherever your umbrella chart's own default values
   live):

   ```yaml
   global:
     canary:
       enabled: true
   ```

   This expands the `gatewayapi` chart's HTTPRoute into the stable/canary backendRef
   pair and arms the Rollout's `trafficRouting`. Since (2) above renders in the same
   sync, this isn't a cold start — it just starts routing a small, already-safe slice
   of traffic per `canary.steps` (defaults to pausing indefinitely at the first step
   until promoted).

None of the three touches the other's inputs — deleting the old block only drops
already-redundant rproxy pods from the main Service's selector, `canary.initialReplicas`
only stands up new infra alongside it with no live traffic until `global.canary.enabled`
is also true, and that flag is what (3) sets in the same sync — so there's no ordering
dependency to stage across separate PRs.

Merge, then confirm: no leftover `-rproxy`/`-control` resources, the main Service's
selector back to its normal specific form, old plain Deployments show `0/0` (retired by
`scaleDown: onsuccess` once their Rollout took over — expected, not a problem), and the
Rollout shows full desired replica count and `Healthy`.

### `OutOfSync` is expected when the chart first lands on Argo Rollouts

Once a Rollout is managing a Service's selector and the HTTPRoute's backendRef
weights (both land in step 2), Argo CD will show the Application as `OutOfSync` — it
sees the controllers' live patches as drift from Helm's static rendered values. This
is expected, not a sign that anything is broken. `syncPolicy.automated.selfHeal: false`
only stops Argo CD from *proactively* reverting that drift between syncs — it does
not stop a sync that happens anyway

## Opting a single deployment out of canary

`global.canary.enabled` is a single toggle at the umbrella-chart level, driving every
deployment alongside it into canary together. Set this chart's own
`canary.enabled: false` to opt one deployment out regardless of that toggle: it always
renders a plain Deployment with a static `replicaCount`, never a Rollout, and no
canary/stable Services. Use this for a deployment pinned to an exact replica count by an
invariant a transient extra canary Pod would violate.

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
is enabled — the Deployment and the Rollout both resolve it from the same
`common.gracefulRolloutValue` helper call, with no separate `canary.minReadySeconds`
override, so the two can't drift independently. But the Rollout still needs its own
explicit line to pick that shared value up: `workloadRef` only copies the referenced
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
