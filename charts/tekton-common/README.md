# tekton-common

A Kubernetes Helm chart to create common resources to run Tekton tasks and
pipelines in a namespace.

In each namespace, much of the configuration for RBAC, secrets, and ingress are
similar. This chart creates those resources in the appropriate namespaces.

## Add Development Namespace

To add a new development namespace, besides adding to the Helm chart, the
following changes are also required:

- Add a DNS record for the webhook in the [terraform
repo](https://github.com/dave-inc/terraform/blob/master/dns/public/trydave.com/A-records.tf)
- Add the Google workload identity to the `tekton-pipelines-dev` service account
in the [terraform repo](https://github.com/dave-inc/terraform/blob/master/projects/internal-1/iam/bindings.tf)
- Add GitHub webhook secret to Secret Manager:
  ```sh
  echo -n "mysecret" | gcloud secrets create gh-general-wh-secret-<namespace> --project dpe-internal-6622 --data-file=-`
  ```
- Add an Argo CD application for the Tekton triggers, tasks, and pipelines. Example:
  ```yaml
  apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: general-1-tekton-dev-<name>
  annotations:
    argocd.argoproj.io/manifest-generate-paths: .
spec:
  destination:
    namespace: <devnamespace>
    server: https://kubernetes.default.svc
  source:
    repoURL: 'git@github.com:dave-inc/tekton'
    targetRevision: dev-<name>
    directory:
      include: '{pipelines/*,tasks/*,triggers/*}'
      recurse: true
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  ```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonLabels | object | {} | Labels to apply to resources |
| development.namespaces | object | {} | Tekton development namespaces |
| development.serviceAccount.annotations | object | {} | Annotations to add to the development ServiceAccount for running Tekton tasks and pipelines |
| secrets.argo | list | [] | List of argo token secrets |
| secrets.pipeline | list | [] | List of secrets to synchronize from Secret Manager |
| secrets.serviceAccount.name | string | tekton-secrets | Name of ServiceAccount used for secrets |
| secrets.serviceAccount.annotations | object | {} | Annotations to add to the ServiceAccount for secrets |
| serviceAccount.annotations | object | {} | Annotations to add to the ServiceAccount for running Tekton tasks and pipelines |
| serviceAccount.name | string | tekton-pipelines | Name of ServiceAccount used for running Tekton tasks and pipelines |
| webhooks | list | [] | Event listener webhooks |
