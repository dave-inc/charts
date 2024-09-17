# Dave Helm Charts
Collection of common sub charts to bootstrap common applications

## Prereq
1. Helm 3.14

## To develop locally
1. Choose chart you wish to update. For example `common`. Update `charts/common/Chart.yaml` version to whatever semver you plan on with a suffix of the jira ticket. For example, `1.0.0-bei-719`
2. In the sre repo cd into the directory of the chart you wish to test. For example `notification-service`
3. With your current directory of charts/notification-service/public update the Chart.yaml file to point to the local file system path and the updated version you chose in step 1. Below shows an example `sre/charts/notification-service/production/Chart.yaml`

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

## To beta test your changes from a feature branch
1. Create a PR
2. Manually run the GHA workflow described in `release.yaml`. This will publish the charts as artifacts in GHA. You then should be able to use them like you did under the development section except pointing repository to the `https://dave-inc.github.io/charts` instead of `file://`

## To create release
1. Remove the jira suffix from the version and get approvals from #sre-support
2. Merge to master. This should automatically trigger the `release workflow`