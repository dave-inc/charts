# Dave Helm Charts
Collection of common sub charts to bootstrap common applications

## Prereq
1. Helm 3.14

## To develop locally
1. Choose chart you wish to update. For example `common`. Update `charts/common/Chart.yaml` version to whatever semver you plan on with a suffix of the jira ticket. For example, `1.0.0-bei-719`
2. In the sre repo cd into the directory of the chart you wish to test. For example `notification-service`
3. With your current directory of charts/notification-service/production update the Chart.yaml file to point to the local file system path and the updated version you chose in step 1. Below shows an example `sre/charts/notification-service/production/Chart.yaml`

```
apiVersion: v2
name: notification-service
version: 1.0.0
dependencies:
  - name: common
    version: 1.0.0-bei-719 #<-- Note!
    repository: "file://../charts/charts/common" #<--Note!
    alias: notification-service
...
  ```
4. Run `helm dependency update`. This will copy over the chart into this repo. Make you you don't commit it.
5. Run `helm template .`. This will render out the Kubernetes manifest objects with the variables replaced to the `stdout`. The output should be a valid yaml file that could be directly applied in a GKE cluster. If there are errors the templating engine will write it to the `stderr`

## Unit testing

We use [helm-unittest](https://github.com/helm-unittest/helm-unittest), a `helm` plugin that renders a chart's templates for a given set of values and asserts on the rendered output (e.g. a field's value, whether a key exists). No cluster is needed — it's checking what `helm template` would produce, not whether a live cluster accepts it.

Install the plugin once locally:

```sh
helm plugin install https://github.com/helm-unittest/helm-unittest --version v1.1.2
```

Run every chart's tests from the repo root:

```sh
make test
```

This finds every chart with a `tests/` directory (e.g. `charts/common/tests`) and runs `helm unittest` against it, so it picks up new charts automatically as they gain coverage. To run a single chart's tests directly:

```sh
cd charts/common
helm unittest .
```

The `Helm Unit Tests` GitHub Actions workflow (`.github/workflows/unit-test.yml`) runs the same thing on every PR.

### Adding a new test

Tests live under `charts/$chart_name/tests/`, one suite file per template, named `<template-basename>_test.yaml` (e.g. `charts/common/tests/pdb_test.yaml` tests `templates/pdb.yaml`). A suite can have multiple `it:` cases, each setting different values and asserting on the result:

```yaml
suite: PodDisruptionBudget
templates:
  - pdb.yaml
values:
  - ./fixtures/minimal-values.yaml
set:
  podDisruptionBudget:
    enabled: true
tests:
  - it: defaults minAvailable to 15% when neither minAvailable nor maxUnavailable is set
    asserts:
      - isKind:
          of: PodDisruptionBudget
      - equal:
          path: spec.minAvailable
          value: "15%"
```

If a template needs values that are `required` elsewhere in the chart (e.g. `common.name`) just to render at all, add them to the shared `charts/$chart_name/tests/fixtures/minimal-values.yaml` and load it via `values:` rather than repeating `set:` boilerplate in every suite.

Good candidates for a new test are anything that's easy to get subtly wrong without `helm lint`/`helm template` catching it — a `.enabled` toggle that's gated in some templates but not others, a label selector, a name derived from a helper. See the [helm-unittest docs](https://github.com/helm-unittest/helm-unittest/blob/master/DOCUMENT.md) for the full list of available assertions.

## Validations through JSON schema

> [!WARNING]
> As it is right now, the `json_schema_bundler.yml` workflow is unable to push commits by itself
>
> Reach out to SRE if you need to update the `values.schema.json` file

We use JSON schema to validate our custom charts. To enable that feature a `values.schema.json` file at the root directory for a given chart must be present. e.g. `charts/common/values.schema.json`.

Both `helm template`, `helm lint` are JSON schema aware. `helm template` in specific is what ArgoCD uses to render the kubernetes manifests.

For our use case, we have decided to have a means to bundle together the schema files that can be found under the root directory for any given chart (e.g. `charts/common/schemas`) into a resulting `values.schema.json` file. This file gets created by [json-schema-bundler](https://www.npmjs.com/package/@skriptfabrik/json-schema-bundler) through the  [json_schema_bundler.yml](https://github.com/dave-inc/charts/blob/master/.github/workflows/json_schema_bundler.yml) workflow. The main entrypoint for the schemas is `charts/$chart_name/schemas/schema.yaml`. That file should include references to other subschemas so we can leverage modularization.

The reason  we don't use plain `$refs` pointing to a file path is because resolving those references becomes difficult since we have to account for absolute paths, relative paths, and `helm` being able to resolve them under all circumstances. The bundler takes care of that for us.

`json-schema-bundler` also has the benefit of allowing us to use yaml files as schemas improving readability. The bundler will convert them to json before rendering the final `values.schema.json` file.

### Local validations

If you want to introduce a new schema or update an existing one, you can do so by creating a new yaml file under `charts/common/schemas` and then referencing it in `charts/common/schemas/schema.yaml`. The bundler will take care of the rest.

Install [json-schema-bundler](https://www.npmjs.com/package/@skriptfabrik/json-schema-bundler) locally and test things out this way:

```sh
npm install -g @skriptfabrik/json-schema-bundler
cd ${charts_repo}/charts/common
json-schema-bundler -d schemas/schema.yaml > values.schema.json
helm lint .
```

That should be enough to get you started with JSON schema validations.

Remember that `values.schema.json` is a generated file and should not be committed to the repo. The bundler will take care of that for you when the workflow runs.

## To beta test your changes from a feature branch
1. Create a PR
2. Manually run the GHA workflow described in `release.yaml`. This will publish the charts as artifacts in GHA. You then should be able to use them like you did under the development section except pointing repository to the `https://dave-inc.github.io/charts` instead of `file://`

## To create release
1. Remove the jira suffix from the version and get approvals from #sre-support
2. Merge to master. This should automatically trigger the `release workflow`
