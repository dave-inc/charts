# Tekton scheduled pipelines

This just assists runing tekton pipelines on a schedule

This chart creates an `EventListener` for all jobs, `Trigger`, `TriggerBindings` and `Cron` for each scheduled job. `TriggerTemplate` must be provided from outside.

### Values.yaml


Minimal example:

```yaml
eventListener: {}
jobs:
  sentinel:
    schedule: "*/1 * * * *"
    triggerTemplate: "wat"
    params:
      repo: "tekton"
```

All possible options (default values used as an example):

```yaml
eventListener:
  name: "tekton-cron"
  replicas: 2
  serviceAccountName: "tekton-pipelines"
jobs:
  sentinel:
    schedule: "*/1 * * * *"
    triggerTemplate: "wat"
    params:
      repo: "tekton"
```
