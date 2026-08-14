# Release pipeline

How a chart change becomes a published release, and which repository settings the
pipeline depends on to work correctly.

## Moving parts

Three workflows split the job, and none does another's work.

`schemas.yml` keeps generated files current. When a PR touches a chart's
`schemas/` directory it rebuilds that chart's `values.schema.json` and pushes the
result to the PR branch. `helm lint` regenerates and fails on any leftover
difference, which covers fork PRs that this workflow cannot push to.

`release-please.yml` decides versions. On every push to `master` it opens or
updates a single PR that bumps `version` in each changed chart's `Chart.yaml`,
writes that chart's `CHANGELOG.md`, and records the new version in
`.release-please-manifest.json`. It does not tag and does not publish, because
`skip-github-release` is set in `release-please-config.json`.

`release.yml` publishes. Merging the release PR lands the version bumps on
`master`, which runs chart-releaser: it packages any chart whose `Chart.yaml`
version has no matching tag, tags it, creates the GitHub Release, and updates
`index.yaml` on `gh-pages`. This is unchanged from how the repo worked when
versions were edited by hand.

The two are coupled in one non-obvious way. release-please works out "what did I
last release" from the GitHub Releases that chart-releaser creates, cross-checked
against `.release-please-manifest.json`. If the Releases are missing, release-please
scans too far back and proposes versions that include already-released commits.

## Repository settings this depends on

These are not cosmetic. Each one is load-bearing, and the failure mode for most of
them is silence rather than an error.

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

### Required status checks

`SOC-CI` and `Codeowners Enforcement` are already required. Add:

- `lint-pr-title`, because release-please treats a non-conventional subject as "no
  release". An unlinted title does not fail, it publishes nothing, and the chart
  quietly stops releasing until someone notices.
- `lint`, so charts are linted and the release config is checked for drift.

Making `lint` required means bot pushes must come from `AUTOMATION_TOKEN`, for the
reason in the next section.

### Let Actions create pull requests, or configure `AUTOMATION_TOKEN`

One of these is **required**, not optional. Without either, release-please fails
outright with:

```
GitHub Actions is not permitted to create or approve pull requests.
```

`GITHUB_TOKEN` cannot open a PR unless the repository or organization enables
*Allow GitHub Actions to create and approve pull requests*. That setting is off by
default. Note the API field is `can_approve_pull_request_reviews`, which is
misleadingly named: it gates creating PRs too, not just approving them.

The alternative is `AUTOMATION_TOKEN`, a PAT or GitHub App token, which is not
subject to that restriction. `release-please.yml` and `schemas.yml` both read it
and fall back to `GITHUB_TOKEN`.

Even with the setting enabled, `AUTOMATION_TOKEN` is worth having, because GitHub
does not start workflow runs from pushes or PRs made with `GITHUB_TOKEN`:

- The release PR gets no `lint` run. `SOC-CI` and `Codeowners Enforcement` are
  dispatched from other repositories, so they still report and the PR stays
  mergeable.
- When `schemas.yml` commits a rebuilt schema, no check re-runs against the new
  commit. If `lint` is a required check, its result sits on the previous commit
  and the PR cannot be merged until something else pushes.

The second is the one that bites.

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
