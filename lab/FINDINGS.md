# Findings — Part 4 Debug Lab

## Summary

Five defects have been identified in the Helm chart during the investigation. The corresponding manifest or configuration changes are documented below.

The lab was reset before the latest verification run. Therefore, the current deployment must be tested again before claiming that all defects are resolved.

The sixth defect remains unconfirmed and requires further investigation.

**Files preserved:** `scenario.sh` and everything under `cluster-state/` must remain unchanged.

---

## Defect 1 — Invalid migration Job restart policy

**Symptom**

The original Kubernetes error was:

```text
Job.batch "migrate" is invalid:
spec.template.spec.restartPolicy: Required value:
valid values: "OnFailure", "Never"
```

**Root cause**

The migration Job template used `restartPolicy: Always`, which is not supported for Kubernetes Job pod templates.

**Fix**

Changed the migration Job restart policy to:

```yaml
restartPolicy: Never
```

This allows the Job controller to manage retries according to `backoffLimit`.

**Verification**

```bash
helm lint ./broken-chart
helm template debug-lab ./broken-chart \
  --namespace debug-lab \
  --show-only templates/migrate-job.yaml

./scenario.sh up
kubectl -n debug-lab describe job migrate
kubectl -n debug-lab get jobs,pods
kubectl -n debug-lab logs job/migrate
```

**Status:** Manifest correction made; fresh deployment verification pending.

---

## Defect 2 — Reporter RoleBinding targets the wrong ServiceAccount

**Symptom**

The original verification output included:

```text
FAIL ServiceAccount debug-lab/reporter cannot list pods
```

**Root cause**

The reporter Deployment uses the `reporter` ServiceAccount, but the original RoleBinding granted permissions to the `default` ServiceAccount.

**Fix**

Changed the RoleBinding subject to:

```yaml
subjects:
  - kind: ServiceAccount
    name: reporter
    namespace: {{ .Release.Namespace }}
```

The Role retains its narrowly scoped `get` and `list` permissions on Pods.

**Verification**

```bash
kubectl -n debug-lab get rolebinding reporter-read -o yaml

kubectl auth can-i list pods \
  -n debug-lab \
  --as=system:serviceaccount:debug-lab:reporter
```

**Earlier evidence:** The authorization check subsequently returned `yes`. This confirms that the permission check passed at that time, but does not establish the root cause of the reporter's separate JSON parsing error.

**Status:** Binding correction made; recheck after redeployment.

---

## Defect 3 — Kubernetes cannot verify the named non-root user

**Symptom**

Pod events reported:

```text
Error: container has runAsNonRoot and image has non-numeric user (nonroot), cannot verify user is non-root
```

**Root cause**

The image specifies the username `nonroot`. Kubernetes could not verify that named user as non-root from the image configuration alone.

The image inspection documented in the debugging guide identified the corresponding numeric UID as `65532`.

**Fix**

Added the following setting to the security context of the affected workloads and migration Job:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

The existing security restrictions are retained.

**Affected templates**

- `backend.yaml`
- `gateway.yaml`
- `metrics.yaml`
- `reporter.yaml`
- `worker.yaml`
- `migrate-job.yaml`

**Verification**

```bash
grep -n -A7 'securityContext:' \
  broken-chart/templates/{backend,gateway,metrics,reporter,worker}.yaml \
  broken-chart/templates/migrate-job.yaml

helm lint ./broken-chart
kubectl -n debug-lab get pods -o wide
kubectl -n debug-lab get events \
  --sort-by=.metadata.creationTimestamp
```

**Status:** Security-context correction made; verify that all affected pods start successfully.

---

## Defect 4 — Gateway points to the wrong backend namespace

**Symptom**

The original verification output included:

```text
FAIL gateway /status does not report backend=ok
```

**Root cause**

The gateway originally referenced:

```yaml
BACKEND_URL: "http://backend.default.svc:8080"
```

However, the backend Service is deployed in the `debug-lab` namespace.

**Fix**

Updated the URL to:

```yaml
BACKEND_URL: "http://backend.debug-lab.svc.cluster.local:8080"
```

**Verification**

```bash
kubectl -n debug-lab get svc backend -o yaml
kubectl -n debug-lab logs deploy/gateway --tail=100
./scenario.sh verify
```

The gateway check passes when its `/status` response contains `"backend":"ok"`.

**Earlier evidence:** An in-cluster request previously returned HTTP 200 and `"backend":"ok"`. The current deployment must be checked again after the reset.

**Status:** URL correction made; fresh verification pending.

---

## Defect 5 — Metrics exceeds the cluster CPU limit

**Symptom**

The original metrics configuration requested 2 CPU cores and specified a CPU limit of 4 cores.

**Root cause**

The namespace's `LimitRange`, defined in `cluster-state/limits.yaml`, specifies a maximum of 1 CPU per container. The original metrics CPU limit exceeded this maximum.

**Fix**

Updated the metrics resources to:

```yaml
resources:
  requests:
    cpu: "50m"
    memory: "64Mi"
  limits:
    cpu: "200m"
    memory: "128Mi"
```

The cluster's `LimitRange` was not modified.

**Verification**

```bash
grep -n -A12 '^metrics:' broken-chart/values.yaml
cat cluster-state/limits.yaml

helm lint ./broken-chart

kubectl -n debug-lab describe pods
kubectl -n debug-lab get events \
  --sort-by=.metadata.creationTimestamp
```

Confirm that the metrics pod is admitted and becomes Ready.

**Status:** Resource correction made; fresh deployment verification pending.

---

## Defect 6 — Additional defect not yet confirmed

**Status:** Unconfirmed.

No additional defect should be claimed without evidence from the remaining verification failures, application logs, Kubernetes events, or manifest inspection.

The reporter previously logged:

```text
pod list failed: parse pod list: unexpected end of JSON input
```

Its `/healthz` endpoint returned HTTP 503. The reporter ServiceAccount's permission to list Pods had also previously been confirmed.

The JSON parsing failure's root cause was not established. It should not automatically be attributed to RBAC.

**Next diagnostic steps**

```bash
kubectl -n debug-lab get pods -o wide
kubectl -n debug-lab logs deploy/reporter --tail=100
kubectl -n debug-lab describe deployment reporter
kubectl -n debug-lab get endpoints reporter -o yaml
./scenario.sh verify
```

Use the fresh output to determine whether the reporter failure persists and whether another defect is responsible.

---

## Final verification

Run the verifier against the current deployment:

```bash
./scenario.sh up
./scenario.sh verify
```

If any checks fail, record their exact output and investigate the relevant workloads before making further changes.

### Final status

| Check | Status |
|---|---|
| Migration Job restart policy | Corrected; verify |
| Reporter RBAC binding | Corrected; recheck |
| Non-root security context | Corrected; verify all workloads |
| Gateway backend URL | Corrected; verify |
| Metrics CPU resources | Corrected; verify |
| Sixth defect | Not confirmed |

**Conclusion:** Five manifest/configuration corrections are documented. The current deployment has not yet been proven to pass the verifier. No claim of `ALL GREEN` should be made until the actual verification output confirms it.