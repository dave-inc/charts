# Contributing

## Do not edit chart versions

`version` in `Chart.yaml` is managed by release-please. Editing it by hand will
be overwritten, and the old habit of tacking a Jira suffix onto the version
(`1.0.0-bei-719`) is no longer how you test a branch. See
[Testing a chart before release](#testing-a-chart-before-release).

## Your PR title is the only thing that matters

Merge your PR with **Squash and merge**. Your PR title then becomes the single
commit message on `master`, and that message is what release-please parses to
decide the next version. Commit messages inside your branch are discarded, so
they are not linted and do not need to follow any convention.

This matters more than it looks. release-please walks every commit reachable from
`master`, not just the first-parent chain. If a PR is merged with a merge commit
instead, each individual branch commit is parsed for a release trigger, and a
stray `feat:` or `BREAKING CHANGE:` in a work-in-progress commit will cut a
release you did not intend. Squashing is what keeps the release surface equal to
the title CI actually checked.

Titles follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>
```

| Type | Version impact |
| --- | --- |
| `feat` | minor bump (`0.3.1` to `0.4.0`) |
| `fix` | patch bump (`0.3.1` to `0.3.2`) |
| `feat!`, or `BREAKING CHANGE:` in the body | major bump (`0.3.1` to `1.0.0`) |
| `chore`, `docs`, `refactor`, `test`, `ci`, `build`, `style` | no release |

A scope is optional and has no effect on which chart is released. Use one if it
helps a human read the log.

## How a change becomes a release

Charts are attributed **by file path**, not by scope. A commit touching
`charts/common/**` releases `common`, and nothing else. A commit touching two
charts releases both.

1. You merge a PR titled `fix: correct probe defaults`, touching `charts/job/`.
2. release-please opens or updates a PR called
   `chore(master): release`. It bumps `version` in `charts/job/Chart.yaml`,
   writes `charts/job/CHANGELOG.md`, and records the new version in
   `.release-please-manifest.json`.
3. That release PR sits open and accumulates further merges until someone merges
   it. Nothing is published before then, so merging to `master` is safe.
4. Merging the release PR lands the version bump on `master`, which triggers
   chart-releaser: it packages the chart, tags `job-0.3.2`, creates the GitHub
   Release, and updates `index.yaml` on `gh-pages`.

Step 4 is unchanged from how this repo has always worked. The only difference is
that a bot writes the version bump instead of you.

### The release PR and SOC-CI

SOC-CI validates that every pull request references an open Jira ticket, and it
does not exempt the release bot. Its only bypass is a hardcoded Dependabot user
id. The release PR is generated, so it has no ticket of its own.

`pull-request-footer` in `release-please-config.json` carries a standing ticket
reference, [SRE-7412](https://demoforthedaves.atlassian.net/browse/SRE-7412), to
satisfy that check. Two things follow from this:

- **SRE-7412 must never be closed.** It is a permanent Epic labelled
  `do-not-close` for exactly this reason. SOC-CI rejects any ticket whose status
  category is `done`, so closing it breaks every future release PR with an error
  that points at Jira rather than at this repo. CI checks that a reference is
  present, but it cannot check that the ticket is still open.
- The individual PRs that feed a release still need their own tickets. The
  standing ticket covers the generated PR only.

### Sweeping changes

Because attribution is by file path, a change that touches every chart releases
every chart. Renaming a shared label or reformatting all `values.yaml` files will
produce eight releases. If that is not what you want, split the change so each
chart moves on its own PR, or use a non-releasing type like `chore`.

## Testing a chart before release

Package the chart locally and point your consuming chart at the tarball. Nothing
needs to be published, and no version needs to be invented.

```sh
cd charts/common
helm dependency update .
helm package . -d /tmp/charts
```

Then in the consuming repo:

```yaml
dependencies:
  - name: common
    version: 0.11.0
    repository: "file:///tmp/charts"
```

## Adding a chart

1. Create `charts/<name>/` with a `Chart.yaml` whose `name` matches the
   directory name. CI enforces this, because release-please derives the release
   tag from `Chart.yaml`'s `name` while chart-releaser derives it from the
   directory.
2. Add the path to `release-please-config.json` under `packages`.
3. Add the path to `.release-please-manifest.json` with the version you consider
   already released. Use `0.0.0` for a brand new chart.

CI fails if a chart is missing from either file, since a chart release-please
does not know about is silently frozen forever.

## Schemas

`values.schema.json` is generated from each chart's `schemas/` directory but is
committed to the repo, because Helm needs it at install time.

You do not have to regenerate it. When a PR touches anything under a chart's
`schemas/`, the Bundle Schemas workflow rebuilds `values.schema.json` and pushes
the result to your branch as a `chore(schemas):` commit. Pull before you push
again, or you will conflict with it.

If you would rather not wait for CI, or your PR comes from a fork where the
workflow cannot push for you:

```sh
make schemas
```

`helm lint` regenerates and fails on any remaining difference, so a stale schema
cannot reach a release either way.
