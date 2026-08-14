# Repository setup for the release pipeline

The release pipeline is inert until four repository settings change on
`dave-inc/charts`. Three of them fail loudly. One fails silently, and that is the
one to care about most.

All four are repository-level and need the **Admin** role on the repo. None of them
need org admin, and none of them touch the existing org rulesets.

The reasoning behind each setting is in
[release-pipeline.md](release-pipeline.md#repository-settings-this-depends-on).
This page is the checklist.

## Do step 4 last

Step 4 makes `lint` and `lint-pr-title` required. Those workflows must already be
on `master` before it is applied, or every open PR becomes unmergeable against
checks that cannot run. Steps 1 through 3 are safe to apply in any order.

## 1. Squash merging only

Current state is the GitHub default: all three merge methods enabled, squash title
`COMMIT_OR_PR_TITLE`, squash message `COMMIT_MESSAGES`.

```bash
gh api -X PATCH repos/dave-inc/charts \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=BLANK
```

In the UI this is Settings, General, Pull Requests.

Verify:

```bash
gh api repos/dave-inc/charts \
  --jq '{allow_squash_merge, allow_merge_commit, allow_rebase_merge,
         squash_merge_commit_title, squash_merge_commit_message}'
```

This is the setting whose failure mode is silent. Under merge commits,
release-please parses every individual branch commit, so an abandoned `feat: wip`
cuts a minor release. Under `COMMIT_MESSAGES`, a stray `BREAKING CHANGE:` footer in
any branch commit cuts a major.

The org ruleset `Copilot-PR-Review` lists `allowed_merge_methods` as `merge`,
`squash` and `rebase`. That does not conflict with this change and does not need an
org admin. The effective set is the intersection of the ruleset and the repository
setting, so restricting the repository to squash is sufficient.

## 2. Allow Actions to create pull requests

Without this, release-please fails outright on its first run with
`GitHub Actions is not permitted to create or approve pull requests`.

In the UI this is Settings, Actions, General, Workflow permissions, the checkbox
reading *Allow GitHub Actions to create and approve pull requests*.

By API, read the current value first, because the PUT replaces both fields and the
`default_workflow_permissions` value should be preserved rather than guessed:

```bash
gh api repos/dave-inc/charts/actions/permissions/workflow

gh api -X PUT repos/dave-inc/charts/actions/permissions/workflow \
  -F can_approve_pull_request_reviews=true \
  -f default_workflow_permissions=<value read above>
```

The API field name `can_approve_pull_request_reviews` is misleading. It gates
creating pull requests, not only approving them.

If org policy forbids this setting, skip it and do step 3, which is not subject to
the restriction.

## 3. `AUTOMATION_TOKEN` secret

Step 2 or step 3 is required. Step 3 is worth doing even when step 2 is done.

GitHub does not start workflow runs from pushes or pull requests made with
`GITHUB_TOKEN`. Two consequences:

- The release PR gets no `lint` run. `SOC-CI` and `Codeowners Enforcement` are
  dispatched from other repositories, so they still report and the PR stays
  mergeable.
- When `schemas.yml` commits a rebuilt schema, nothing re-runs against the new
  commit. With `lint` required, its result sits on the previous commit and the PR
  cannot be merged until something else pushes. This is the one that bites.

Create a fine-grained PAT or GitHub App installation token scoped to
`dave-inc/charts` with `contents: write` and `pull requests: write`, then add it as
a repository secret named `AUTOMATION_TOKEN` under Settings, Secrets and variables,
Actions.

`release-please.yml` and `schemas.yml` both read it and fall back to
`GITHUB_TOKEN`, so adding it later is a no-op for anything already working.

Whichever identity owns the token becomes the author of the release PR. That
identity does not bypass `SOC-CI`; the only bypass in the SOC-CI workflow is a
hardcoded Dependabot user id. This is why the release PR carries a Jira reference
in its footer.

## 4. Required status checks

Add `lint` and `lint-pr-title` as required checks on the default branch.

The three rulesets already on this repo, `SOC-CI`, `Enforce Codeownership 2.0` and
`Copilot-PR-Review`, are all `source_type: Organization`. A repo admin cannot edit
them and should not try. Rulesets are additive, so a new repository-level ruleset
layers on top without disturbing them:

```bash
gh api -X POST repos/dave-inc/charts/rulesets --input - <<'EOF'
{
  "name": "Release pipeline checks",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [{
    "type": "required_status_checks",
    "parameters": {
      "strict_required_status_checks_policy": false,
      "do_not_enforce_on_create": true,
      "required_status_checks": [
        { "context": "lint" },
        { "context": "lint-pr-title" }
      ]
    }
  }]
}
EOF
```

`lint-pr-title` matters because release-please treats a non-conventional PR title
as "no release". An unlinted title does not fail anything, it publishes nothing,
and the chart quietly stops releasing until someone notices.

Verify, then confirm an open PR still reports `MERGEABLE`:

```bash
gh api repos/dave-inc/charts/rulesets --jq '.[] | select(.source_type=="Repository") | .name'
gh pr view <any open PR> --repo dave-inc/charts --json mergeable,mergeStateStatus
```

## What was already verified

Steps 1, 2 and 4 were applied to a fork of this repo and exercised end to end
before being written down here.

- The step 1 command returned exactly the intended state.
- The step 4 ruleset was accepted as written.
- A pull request touching only a documentation file, which is the case most likely
  to expose a required check that never fires, came back `MERGEABLE` with
  `mergeStateStatus: CLEAN` and both `lint` and `lint-pr-title` completing
  successfully. `schemas.yml` correctly stayed idle and does not block, because it
  is not a required check.
- With step 2 unset, release-please failed with the error quoted above. With it
  set, it opened a release PR, and merging that PR published charts through
  chart-releaser.

## Rollback

Each step reverts independently.

```bash
# 1
gh api -X PATCH repos/dave-inc/charts \
  -F allow_merge_commit=true -F allow_rebase_merge=true \
  -f squash_merge_commit_title=COMMIT_OR_PR_TITLE \
  -f squash_merge_commit_message=COMMIT_MESSAGES

# 2
gh api -X PUT repos/dave-inc/charts/actions/permissions/workflow \
  -F can_approve_pull_request_reviews=false \
  -f default_workflow_permissions=<original value>

# 3: delete the AUTOMATION_TOKEN secret

# 4
gh api -X DELETE repos/dave-inc/charts/rulesets/<id>
```

Reverting step 1 or step 4 leaves the pipeline running in a degraded state rather
than stopping it, which is the argument for reverting step 2 or 3 instead if the
pipeline needs to be switched off in a hurry. Removing the ability to open the
release PR stops it cleanly and changes nothing about how charts already published
are consumed.
