# Dave Helm Charts
Collection of common sub charts to bootstrap common applications

## Prereq
1. Helm 4.2

Chart versions are managed by [release-please](https://github.com/googleapis/release-please)
and must not be edited by hand. See [CONTRIBUTING.md](CONTRIBUTING.md).

## To develop locally
1. Choose the chart you wish to update, for example `common`. Leave its version alone.
2. In the sre repo cd into the directory of the chart you wish to test. For example `notification-service`
3. With your current directory of charts/notification-service/production update the Chart.yaml file to point to the local file system path. Use the chart's current version. Below shows an example `sre/charts/notification-service/production/Chart.yaml`

```
apiVersion: v2
name: notification-service
version: 1.0.0
dependencies:
  - name: common
    version: 0.11.0 #<-- current version from charts/common/Chart.yaml
    repository: "file://../charts/charts/common" #<--Note!
    alias: notification-service
...
  ```
4. Run `helm dependency update`. This will copy over the chart into this repo. Make you you don't commit it.
5. Run `helm template .`. This will render out the Kubernetes manifest objects with the variables replaced to the `stdout`. The output should be a valid yaml file that could be directly applied in a GKE cluster. If there are errors the templating engine will write it to the `stderr`

## Validations through JSON schema

> [!IMPORTANT]
> `values.schema.json` is generated but committed. Run `make schemas` after
> editing anything under a chart's `schemas/` directory. CI regenerates and fails
> if the committed copy is stale.

We use JSON schema to validate our custom charts. To enable that feature a `values.schema.json` file at the root directory for a given chart must be present. e.g. `charts/common/values.schema.json`.

Both `helm template`, `helm lint` are JSON schema aware. `helm template` in specific is what ArgoCD uses to render the kubernetes manifests.

For our use case, we have decided to have a means to bundle together the schema files that can be found under the root directory for any given chart (e.g. `charts/common/schemas`) into a resulting `values.schema.json` file. This file gets created by [json-schema-bundler](https://www.npmjs.com/package/@skriptfabrik/json-schema-bundler) via `make schemas`. The main entrypoint for the schemas is `charts/$chart_name/schemas/schema.yaml`. That file should include references to other subschemas so we can leverage modularization.

The reason  we don't use plain `$refs` pointing to a file path is because resolving those references becomes difficult since we have to account for absolute paths, relative paths, and `helm` being able to resolve them under all circumstances. The bundler takes care of that for us.

`json-schema-bundler` also has the benefit of allowing us to use yaml files as schemas improving readability. The bundler will convert them to json before rendering the final `values.schema.json` file.

### Local validations

If you want to introduce a new schema or update an existing one, you can do so by creating a new yaml file under `charts/common/schemas` and then referencing it in `charts/common/schemas/schema.yaml`. The bundler will take care of the rest.

Regenerate and lint locally:

```sh
make schemas
cd ${charts_repo}/charts/common
helm lint .
```

That should be enough to get you started with JSON schema validations.

`values.schema.json` is generated, but it is committed, because Helm reads it at
install time. Always commit the regenerated file alongside your `schemas/` change.

## To test your changes from a feature branch
Package the chart locally and consume it over `file://`. See
[CONTRIBUTING.md](CONTRIBUTING.md#testing-a-chart-before-release). Nothing needs
to be published to test a branch.

## To create release
1. Merge your PR to master with a `feat:` or `fix:` title.
2. release-please opens a PR titled `chore(master): release` containing the
   version bump and changelog. Get approvals from #sre-support on that PR.
3. Merge the release PR. chart-releaser then packages, tags and publishes.
