# Release pipeline

How a chart change becomes a published release, and which repository settings the
pipeline depends on to work correctly.

## Moving parts

Two workflows split the job, and neither does the other's work.

`schemas.yml` keeps generated files current. When a PR touches a chart's
`schemas/` directory it rebuilds that chart's `values.schema.json` and pushes the
result to the PR branch. `helm lint` regenerates and fails on any leftover
difference, which covers fork PRs that this workflow cannot push to.

`release.yml` does versioning and publishing in two jobs, in that order, so there
is no race between them.

The `release-please` job decides versions. On every push to `master` it opens or
updates a single PR that bumps `version` in each changed chart's `Chart.yaml`,
writes that chart's `CHANGELOG.md`, and records the new version in
`.release-please-manifest.json`. When that PR is merged, the same job creates the
tag and the GitHub Release, using the per-release changelog as the release body.

The `publish` job runs only when the first job actually released something. It
packages those charts, attaches each `.tgz` to the release release-please just
created, and regenerates `index.yaml` on `gh-pages`.

release-please owns the release object, and chart-releaser is reduced to packaging
and indexing. That division is why the publish job drives `cr` by hand instead of
using the chart-releaser action's normal path, which runs `cr upload` and would
replace the changelog body with the chart description.

Neither documented way of suppressing that is usable, and the second is the reason
this is written out rather than configured:

- `skip_upload` makes `cr.sh` return early from `update_index()`, so `index.yaml`
  is never pushed and nothing is installable.
- `skip_existing` is a bare `continue` placed before the asset upload. The release
  keeps its notes and never receives its `.tgz`. Because `cr index` builds entries
  by reading each release's assets, the chart is then absent from `index.yaml`
  while its release page looks perfectly correct.

The jobs are coupled in one non-obvious way. release-please works out "what did I
last release" from the GitHub Releases, cross-checked against
`.release-please-manifest.json`. If the Releases are missing, release-please scans
too far back and proposes versions that include already-released commits.

### Release tags must point at a commit that touches the chart

release-please turns a release into a starting point by filtering commits to the
chart's path *first*, then looking for the release's commit sha in what remains.
If the tag points at a commit that touches no file under that chart, the sha is
never found, the cut-off is lost, and the chart's entire history is reconsidered.
The result is a release PR that proposes a bump built from commits that already
shipped, which looks plausible and is wrong.

This is a real failure that happened while testing, and it is worth recognising
because nothing about it is reported as an error:

```
Found release for path charts/common, common-0.12.0
release for path: charts/common, version: 0.12.0, sha: dbbe643
Considering: 46 commits          <- should have been 0
```

The cause was a tag created by chart-releaser at whatever `HEAD` happened to be
when the publish ran, which was a `ci:` commit touching only a workflow file,
because an earlier publish attempt had failed and the retry landed one commit
later.

Now that release-please creates the tags, it tags its own release commit, which by
construction edits `Chart.yaml` and `CHANGELOG.md` for every chart in the release.
The hazard is designed out rather than guarded against. It only needs
understanding when inheriting tags made some other way, as when this pipeline is
first switched on.

The fix, if it happens, is to repoint the offending tag at the release commit:

```bash
gh api -X PATCH repos/OWNER/REPO/git/refs/tags/TAG -f sha=RELEASE_COMMIT -F force=true
```

Verify with a dry run, which should report `Considering: 0 commits` for every
untouched package:

```bash
npx release-please release-pr --token="$(gh auth token)" --repo-url=OWNER/REPO \
  --config-file=release-please-config.json \
  --manifest-file=.release-please-manifest.json --dry-run --debug
```

## Repository settings this depends on

These are not cosmetic. Each one is load-bearing, and the failure mode for most of
them is silence rather than an error.

This section explains why. [repo-setup.md](repo-setup.md) is the checklist for
applying them, written for whoever holds admin on the repo.

### Squash merging only

Set **Squash and merge** as the only allowed merge method. Disable merge commits
and rebase merging.

release-please walks every commit reachable from `master`, not only the
first-parent chain. Under merge commits, every individual branch commit is parsed
for a release trigger, so a work-in-progress commit reading `feat: wip` cuts a
minor release nobody asked for. Squashing reduces each PR to exactly one commit
whose message is the PR title, which is the string CI already checked.

### Squash commit title: `PR_TITLE`

The GitHub default is `COMMIT_OR_PR_TITLE`, which uses the *commit* subject when a
PR contains exactly one commit. That silently bypasses PR title linting for
single-commit PRs, which are the common case for small chart fixes.

### Squash commit message: `BLANK`

The default `COMMIT_MESSAGES` concatenates every branch commit message into the
squash commit body, and release-please parses that body for `BREAKING CHANGE:`
footers. One such line in an abandoned work-in-progress commit produces a major
version bump.

With `BLANK`, a major release is requested explicitly with `!` in the title, as in
`feat(common)!: drop support for x`. That is the only path to a major, which is
the point.

### `lint` and `lint-pr-title` are not required checks

They run on every PR and report failures, but nothing blocks on them, and that is
deliberate.

Requiring them breaks releases outright. The release PR is opened by a bot, GitHub
does not start workflow runs for it, so it reports zero checks and sits at
`mergeStateStatus: BLOCKED`. A ruleset without bypass actors cannot be overridden
by anyone, so even `gh pr merge --admin` fails. The only escape is disabling the
ruleset, merging, and re-enabling it, once per release, by hand.

They would also be checking nothing useful at that point. Every commit in the
release PR was linted on its own PR, and the PR title is generated by
release-please, so `lint-pr-title` would be grading a machine against a machine.

`SOC-CI` and `Codeowners Enforcement` still gate the release PR. They are
dispatched by an app reacting to webhooks rather than by a workflow in this repo,
and webhook delivery is not subject to the `GITHUB_TOKEN` suppression, so they
report on bot-authored PRs. Combined with a human choosing to merge, that is the
release control.

The cost is that `lint-pr-title` cannot stop a badly titled PR from merging. When
that happens release-please attributes no release to it and the change silently
never ships. It is visible as a failing check before merge.

### Let release-please open its pull request

Something has to make this possible, or release-please fails outright with:

```
GitHub Actions is not permitted to create or approve pull requests.
```

`GITHUB_TOKEN` cannot open a PR unless the repository or organization enables
*Allow GitHub Actions to create and approve pull requests*. That setting is off by
default. Note the API field is `can_approve_pull_request_reviews`, which is
misleadingly named: it gates creating PRs too, not just approving them.

The better option is a GitHub App token, which is not subject to that restriction.
`release.yml` and `schemas.yml` both mint one through the org's shared action and
fall back to `GITHUB_TOKEN` when the app is unavailable. It is scoped to this repo,
minted per run, revoked when the job ends, and not tied to a person.

The app also fixes a quieter problem. GitHub does not start workflow runs from
pushes made with `GITHUB_TOKEN`, so when `schemas.yml` commits a rebuilt schema, no
check re-runs against the new commit and the PR's checks describe the commit
before it.

## Bootstrapping

`.release-please-manifest.json` is seeded with each chart's last stable released
version. release-please maintains it from then on, and the only manual edit is
adding a line when a chart is added.

Seeded values were taken from the newest non-prerelease tag per chart:

| chart | seeded from |
| --- | --- |
| cloudsql-proxy | `cloudsql-proxy-0.1.0` |
| common | `common-0.11.0` |
| dave-npd | `dave-npd-0.3.0` |
| gateway-bundle | `gateway-bundle-2.2.0` |
| gatewayapi | `gatewayapi-2.10.0` |
| job | `job-0.2.1` |
| kyverno-policies | `kyverno-policies-0.1.1` |
| workflow | `workflow-0.1.0` |

The first release PR will therefore replace the hand-maintained `-beta.N` suffixes
currently sitting in `Chart.yaml` with clean stable versions. `common` moves from
`0.11.1-beta.19` to `0.12.0` rather than continuing the beta chain. This looks
like a jump and is expected.

## SOC-CI and the release PR

The release PR is generated, so it has no Jira ticket of its own, and SOC-CI does
not exempt it. Its only bypass is a hardcoded Dependabot user id.

`pull-request-footer` in `release-please-config.json` carries
[SRE-7412](https://demoforthedaves.atlassian.net/browse/SRE-7412), a permanent
Epic labelled `do-not-close` that exists solely to satisfy that check. It follows
the same arrangement already used for Dependabot PRs in `dave-inc/terraform`.

If SRE-7412 is ever closed, every release PR fails SOC-CI, and the error points at
Jira rather than at this repo. `lint` verifies a ticket reference is present but
cannot verify it is still open.

## When something does not release

Work through these in order.

A chart did not release. Check that a commit actually changed a file under that
chart's directory, since attribution is by path and nothing else. A change to a
shared workflow does not release any chart.

Nothing released at all. Check the merged commit's subject on `master`. If it is
not a conventional commit, or its type is `chore`, `docs`, `refactor`, `test`,
`ci`, `build` or `style`, release-please deliberately does nothing.

A chart released a version you did not expect. Compare
`.release-please-manifest.json` against the GitHub Releases for that chart. A
missing Release makes release-please look further back than it should.

The release PR cannot be merged. Confirm SRE-7412 is still open.
