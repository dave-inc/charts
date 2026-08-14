# Demo script: how a chart change becomes a release

A walkthrough to read while showing the release pipeline to other people. Runs
about ten minutes with questions.

Lines in blockquotes are meant to be said out loud. Everything else is what you do
while saying them.

## Before you start

Until the settings in [repo-setup.md](repo-setup.md) are applied to
`dave-inc/charts`, the live parts of this demo only work on the fork at
`danryan-dave/charts`. Once upstream is enabled, swap the repo and the script is
unchanged.

Open these tabs in order, so you are never hunting for a URL mid-sentence.

1. A chart directory, for example `charts/common/Chart.yaml`
2. https://github.com/danryan-dave/charts/pull/3, the release PR from the recorded run
3. https://github.com/danryan-dave/charts/releases
4. A terminal with `helm` on the path

If you want the live version rather than the recorded one, have a small chart edit
ready to push. Budget six minutes of waiting across the two workflow runs, and know
that this is the part of the demo most likely to make you stand around watching a
spinner. The recorded run exists so you do not have to.

## The one-sentence version

Open with this. Some people only need this much.

> You write a pull request title. Everything after that is automatic: the version
> bump, the changelog, the tag, the GitHub release, and the entry in the Helm
> repository index. Nobody edits a version number by hand again.

## Act 1, the problem

About thirty seconds. Do not spend longer, most of the audience already knows.

Show `charts/common/Chart.yaml` and point at the `version` field.

> Today this number is edited by hand in the same PR as the change. Three things go
> wrong with that, and all of them have happened here. People forget, so a change
> ships under a version that already exists. Two PRs in flight pick the same
> number and conflict. And the number is a judgment call, so whether a change is a
> patch or a minor depends on who wrote it and what kind of day they were having.

## Act 2, the change

About two minutes.

Open a normal chart PR. Use a merged one if you are not running live.

> Here is an ordinary change to a chart. The important part is not the diff, it is
> the title.

Point at the PR title.

> The title is a conventional commit. A `fix:` prefix means a patch release. A
> `feat:` prefix means a minor release. That is the entire interface. It is the
> thing a reviewer already reads first, so we are not asking anyone to write
> anything new, we are just giving the existing habit a meaning.

Scroll to the checks.

> Two checks matter here. `lint-pr-title` rejects a title that is not a
> conventional commit. `lint` runs `helm lint` on every chart and checks that the
> release config still covers every chart in the repo.

If someone asks why the title check is required rather than advisory, this is the
best answer and it is worth volunteering:

> If the title is wrong, nothing fails. The tooling reads it, finds no release
> trigger, and publishes nothing. The chart quietly stops releasing and you find
> out weeks later when someone asks where their fix went. A required check turns a
> silent non-event into a red X.

If the PR touches a chart's `schemas/` directory, point that out too.

> The bundled `values.schema.json` is generated from these files, and a bot
> regenerates and commits it back onto the branch. That used to be a manual step
> people forgot.

## Act 3, the merge

About thirty seconds.

Merge, or show the merge commit on an already-merged PR.

> Squash merge, which is the only option enabled. The PR title becomes the commit
> message on master, and the commit body is left empty on purpose. Both of those
> are load-bearing rather than stylistic, and I can explain why afterwards if
> anyone wants it.

Have the reason ready without leading with it:

> The tooling reads every commit on master, not just the merge commits. Under merge
> commits, a work-in-progress commit saying `feat: wip` inside someone's branch
> would cut a minor release on its own. And anything writing `BREAKING CHANGE:`
> into the commit body would cut a major. Squashing to a single reviewed title
> closes both.

## Act 4, the release pull request

The centrepiece. About two minutes. Open
https://github.com/danryan-dave/charts/pull/3.

> Merging to master does not publish anything. It opens this.

Let them read the title, `chore: release master`.

> A bot opened this pull request. It is a proposal: here is what I intend to
> release, and here is what will be in it. Nothing ships until a human merges it.
> That is the review gate, and it is why this is safe to have running
> automatically.

Expand a couple of the collapsed sections in the body.

> Each chart gets its own section with its own changelog, generated from the commit
> messages. This is not a summary anyone wrote, it is the commit titles that were
> already reviewed on their own pull requests.

Open the Files tab.

> Five charts here: cloudsql-proxy, common, job, kyverno-policies and workflow.
> Each one gets a `Chart.yaml` bump and a `CHANGELOG.md`. The repo has more charts
> than that, and the ones that are not listed had no changes, so they are not being
> released. Attribution is by file path, so a change under `charts/common/` can
> only ever release `common`.

This next contrast is the most convincing thirty seconds of the demo, so slow down
for it.

> Look at the version numbers. `common` went from 0.11.0 to 0.12.0, a minor,
> because it picked up commits starting with `feat:`. `kyverno-policies` went from
> 0.1.1 to 0.1.2, a patch, because it only picked up fixes. Nobody decided that.
> The commit messages decided it, and the same rule applies to everyone.

Scroll to the footer of the PR body and point at the Jira reference.

> The release PR carries a Jira ticket reference because SOC-CI checks every pull
> request against an open ticket, and a bot cannot be waved through. It points at a
> standing epic that stays open for exactly this reason. The individual changes in
> the release were each reviewed and ticketed on their own PRs.

## Act 5, publishing

About a minute.

Merge the release PR, or show https://github.com/danryan-dave/charts/releases.

> Merging the release PR is what publishes. For each chart it creates a git tag, a
> GitHub release with the packaged chart attached, and an updated entry in the Helm
> repository index.

Open one release and point at the body.

> The release notes are the same changelog you just read in the release pull
> request, per chart and per version. You are not getting a generic "chart
> description" here, you are getting the list of changes that actually went in.
> Anyone asking "what changed in common 0.12.0" has one page to look at.

Point at the tag names, `common-0.12.0` and similar.

> The tag format is unchanged from what this repo has always used, chart name and
> version with no `v` prefix. That was deliberate. Everything already pointing at
> these tags keeps working, and there was no migration.

Open one of the releases and point at the attached `.tgz`, for example
`common-0.12.0.tgz`.

> The packaged chart is attached to the release, and the index that Helm reads is
> updated on the `gh-pages` branch to point at it. That is the whole publish step.

For the consumer view, use the real production repository rather than the fork,
since the fork's index only contains the fork's runs:

```bash
helm repo add dave https://dave-inc.github.io/charts
helm repo update dave
helm search repo dave/common --versions | head -5
```

> Same repository URL, same commands, same tag format. Nothing changes for anyone
> installing these charts, which is the point. This is a change to how versions get
> decided, not to how charts get consumed.

If you are demoing on the fork, say so rather than letting someone notice that the
version you just released is absent from this list:

> The version I just cut lives in the fork's index, not this one. This list is
> production, and it is here to show that the consumer side is untouched.

## Act 6, closing

> The short version is that the only new thing anyone has to do is write a
> sensible pull request title, which most people already do. In exchange the
> version numbers become correct by construction, the changelogs write themselves,
> and releasing stops being a thing someone remembers to do.

## Questions you will get

Have these ready. The first three come up almost every time.

> **What if I write a bad title?**
> The check fails and you edit the title. It re-runs on edit, no new commit needed.

> **How do I cut a major version?**
> An exclamation mark before the colon, as in `feat(common)!: drop support for x`.
> It is deliberately the only way, so a major is always a decision rather than an
> accident.

> **What if my PR changes two charts?**
> Both get released. Attribution is per file path, so each chart gets whatever bump
> its own changes justify. Prefer separate PRs when the changes are unrelated,
> because the changelog entries read better.

> **What if the release PR sits open for a week?**
> It updates itself as more changes land, so it is always a current proposal rather
> than a stale one. Nothing is lost by leaving it. Merging it more often just means
> smaller releases.

> **Can it release something I did not intend?**
> It can only release charts whose files changed, and only after a human merges the
> release PR. The failure mode we actually guarded against is the opposite one,
> releasing nothing silently, which is what the required title check is for.

> **What happens to the versions currently in Chart.yaml?**
> They are the starting point. Each chart's current released version was recorded
> when this was set up, and bumps continue from there. No chart jumps or restarts.

> **Do we still control when things ship?**
> Yes. The release pull request is a normal PR with normal reviewers and normal
> checks. Not merging it means not shipping.

## If something breaks mid-demo

Nothing here is fatal to the story, so keep going rather than debugging live.

If the release PR has not appeared yet, it is the workflow run on master, which
takes a minute or two. Switch to the recorded PR #3 and carry on.

If a check is stuck as pending, say that the required checks are the point and move
to the recorded run.

If someone spots that upstream `dave-inc/charts` does not have this enabled yet,
that is accurate and worth answering straight:

> Correct. This is running on a fork because turning it on upstream needs four
> repository settings changed by an admin. They are written up, and the pipeline
> itself has been through a full run start to finish, which is what you are
> looking at.
