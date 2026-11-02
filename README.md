<!--
File        : README.md
Assignment  : DSO202 Assignment 4
Descriptor  : Unit IV 4.1 to 4.4 - GitOps with Argo CD
Purpose     : Purpose, pinned versions, build sequence, cleanup, credential
              handling and the written answers Q1 to Q6.
-->
# dso202-gitops

GitOps delivery of the DSO202 three-tier Task Tracker with Argo CD. Everything
that runs after bootstrap is described by a file in this repository: the cluster
fetches its desired state from Git, and no person or pipeline pushes into it.

| | |
|---|---|
| **Environments** | `dso202-dev` follows `main` with automated sync. `dso202-staging` follows a Git tag and is synchronised by a person. |
| **Evidence** | [`docs/evidence.md`](docs/evidence.md), one section per task, with 22 screenshots in [`docs/screenshots/`](docs/screenshots/) |
| **Tags** | `v1.0.0`, `v1.1.0`, `v1.2.0` |
| **Rebuild** | Cluster deleted and rebuilt from this repository plus one key: 212 seconds to a working dev frontend |

Bonus Task 10 was not attempted.

## 1. Pinned versions

| Component | Version |
|---|---|
| Argo CD server and `argocd` client | v3.5.6 |
| Sealed Secrets Helm chart | 2.20.0 |
| Sealed Secrets controller | 0.40.0 |
| `kubeseal` | v0.40.0 |
| kind | v0.32.0 |
| Node image and `kubectl` | v1.36.1 |
| Kustomize, built into `kubectl` | v5.8.1 |
| Helm | v4.3.0 |
| Docker | 29.7.2 |
| Application images | `sarojsanyasi/dso202-{frontend,backend,db}:1.0` |
| Smoke-test image | `busybox:1.37` |

## 2. Layout

| Path | Concern | Applied by |
|---|---|---|
| `cluster/` | kind cluster definition | hand, once |
| `bootstrap/argocd/` | Argo CD install and its settings | hand, once |
| `bootstrap/root/` | `platform` project and the root Application | hand, once |
| `argocd/` | `dso202` project and every other Application | root Application |
| `platform/<env>/` | Namespace, quota, limits, RBAC, sealed credentials | `platform-<env>` Application |
| `charts/tasktracker/` | The chart, identical in both environments | `tasktracker-<env>` Application |
| `environments/<env>/` | Everything that differs between environments | `tasktracker-<env>` Application |

Sync order is set by waves: `dso202` project (-3), Sealed Secrets (-2), platform
(-1), workloads (0). Inside a workload: database (0), backend (1), frontend (2),
then the PostSync smoke test.

## 3. Build from an empty machine

This is the sequence practised in Task 9. It needs Docker, kind, `kubectl` and
the `argocd` client at the versions above, and the sealing key backup from
section 5 in `../dso202-keys/`.

```bash
git clone https://github.com/KeldenPDorji/dso202-gitops.git
cd dso202-gitops
kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
kubectl wait --for=condition=Ready node --all --timeout=300s
```

Restore the sealing key before the controller exists, so that it finds this key
at start-up instead of generating a new one.

```bash
kubectl create namespace sealed-secrets
kubectl apply -f ../dso202-keys/sealing-key.backup.yaml
```

Bootstrap. Nothing else is applied by hand.

```bash
kubectl apply -k bootstrap/argocd --server-side --force-conflicts
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=600s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
kubectl apply -f bootstrap/root
kubectl wait --for=create job/tasktracker-smoke-test -n dso202-dev --timeout=600s
kubectl wait --for=condition=Complete job/tasktracker-smoke-test -n dso202-dev --timeout=240s
```

Run the port-forward in a second terminal and leave it open. Then sign in and
synchronise staging, which is manual by design.

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

```bash
argocd login localhost:8080 --username admin --password "$(argocd admin initial-password -n argocd | head -1)" --insecure
argocd app sync tasktracker-staging
kubectl get applications -n argocd
```

The dev frontend is at `http://localhost:30080`. kind maps only that port, so
staging is reached with `kubectl port-forward -n dso202-staging svc/tasktracker-frontend 8081:8080`
and `http://localhost:8081`.

Local account passwords are not in Git, so the `reviewer` password is set again
after a rebuild with `argocd account update-password --account reviewer`.

**Without the key backup** the committed SealedSecrets cannot be decrypted. Skip
the restore, write new values for `DB_USER`, `DB_PASSWORD`, `POSTGRES_USER` and
`POSTGRES_PASSWORD` into `secrets-plain/dev.env` and `secrets-plain/staging.env`
(ignored by Git), seal them for the new controller, commit the two files, then
delete the plaintext:

```bash
export SEALED_SECRETS_CONTROLLER_NAMESPACE=sealed-secrets
kubectl create secret generic tasktracker-credentials --namespace dso202-dev --from-env-file=secrets-plain/dev.env --dry-run=client -o yaml | kubeseal --format yaml > platform/dev/tasktracker-credentials.sealed.yaml
kubectl create secret generic tasktracker-credentials --namespace dso202-staging --from-env-file=secrets-plain/staging.env --dry-run=client -o yaml | kubeseal --format yaml > platform/staging/tasktracker-credentials.sealed.yaml
```

## 4. Cleanup

```bash
kind delete cluster --name dso202-gitops
```

This removes the cluster, Argo CD and all database contents. The repository and
the key backup are not touched. Keep `../dso202-keys/` private.

## 5. Credential handling

- Credentials reach Git only as SealedSecrets, in
  `platform/<env>/tasktracker-credentials.sealed.yaml`. Each is encrypted for one
  name and one namespace (strict scope).
- Plaintext existed only in `secrets-plain/`, which is ignored by Git and was
  emptied after sealing. Dev and staging use different values.
- The chart never renders a Secret. Pods read the one the controller creates,
  named by the `existingSecret` value.
- The sealing key backup lives outside the repository in `../dso202-keys/`, with
  mode `600`. It is never committed, pasted or stored in an unencrypted cloud
  folder.
- `.gitignore` is only a guard against accidents. The proof is a history search:
  all 4 distinct credential values, their base64 forms and the sealing key return
  no matches in any commit ([evidence](docs/evidence.md#task-4---platform-layer-and-sealed-secrets)).

## 6. Deviations from the brief

| # | Brief | What was done | Why |
|---|---|---|---|
| D1 | Task 7 uses images tagged `1.1` | Config releases on tag `1.0`: `RELEASE` markers through `extraEnv`, with a wrong `DB_HOST` as the faulty release | `dso202-frontend`, `dso202-backend` and `dso202-db` have no `1.1` tag on Docker Hub (checked 3 November 2026). No unissued image was substituted. The rollout, failure, revert and promotion path is the same, but the page header does not change and the log line comes from the injected fault, not from a release note |
| D2 | The whitelist names exactly the kinds the chart renders | `ReplicaSet` and `Pod` were added, commented, in `4a71fc6` | Argo CD hides live objects the project does not permit. With the exact list, the resource tree had no Pods and `argocd app logs` returned nothing for `admin` or `reviewer`, so Task 6 could not show Pod logs. Screenshot 04 records the exact match, and 09 predates the change. No kind forbidden by the brief was added |
| D3 | `root` is not Healthy before the first staging sync | `root` reported `Synced / Healthy` while `tasktracker-staging` was `OutOfSync / Missing` | Recorded as observed. The Listing 4 health check is applied as provided, and the cause was not traced |
| D4 | CRUD on the page at `http://localhost:30080` | The frontend served HTTP 200, and CRUD ran against the API through a port-forward | As in Assignment 1, `BACKEND_URL` is a cluster-internal name that the browser cannot resolve |
| D5 | Quota and limits from Assignment 2 | `services.nodeports` raised from `0` to `1`, and the LimitRange minimum lowered so the smoke-test Job is admitted | The Assignment 2 values reject the NodePort that C10 requires |

Listing 8 was also adjusted as Task 3 expects: `PersistentVolumeClaim` added,
`StatefulSet` and `ServiceAccount` removed because the chart renders neither.

## 7. Written answers

### Q1 - Why is `platform` applied by hand while `dso202` is created by the root?

The root Application belongs to the `platform` project, so that project must
exist before the root can run. Nothing can deliver it, because the thing that
delivers is what depends on it. `dso202` has no such problem: it is an ordinary
object at wave -3 of the root, so its limits are versioned, reviewed by pull
request and restored by self-heal like any other file.

If `dso202` could deploy into the `argocd` namespace, an Application written
there could name any project, including `platform`. A change to a workload could
then create objects with the project's limits removed, which is administrator
capability. The source, namespace and kind restrictions would stop being a
boundary.

### Q2 - What does strict scope prevent, and what happens if the sealing key is lost?

Strict scope mixes the Secret's name and namespace into the encryption. A
SealedSecret copied to another namespace, or renamed, cannot be decrypted. That
stops anyone who can write to one namespace from replaying another environment's
ciphertext to read its credentials, so the dev file cannot serve staging.

If the key is lost, Secrets already in a running cluster keep working, but no
committed SealedSecret can be decrypted on a new cluster, and the platform
Applications fail with `no key could decrypt secret`. The controller must
generate a new key, every credential must be sealed again from its plaintext, and
the new files committed. If the plaintext is gone too, the credentials must be
replaced. The database is then reset or its user's password changed to match.

### Q3 - What is the difference between Synced and Healthy?

Synced compares the cluster with Git: the live objects match the desired
manifests. Healthy describes whether those objects work. They are independent.

The faulty release in Task 7 was Synced but not Healthy:

```text
tasktracker-dev: Synced / Degraded @ b62f699
tasktracker-backend-95c8f7fd5-njfvj 0/1 Running
```

Git described the wrong `DB_HOST` and the cluster matched it exactly, so Argo CD
had nothing to change, but the new Pod never became ready. Drill 4 shows the
reverse: `tasktracker-dev: OutOfSync / Healthy @ 5fe500a`, where Git asked for a
resource the project refused while the running Pods stayed fine.

### Q4 - What do Argo CD RBAC and Kubernetes RBAC control?

Argo CD RBAC controls what a user may do through the Argo CD API, UI and CLI:
reading applications, syncing them, reading logs. It is configured in `policy.csv`
in the `argocd-rbac-cm` ConfigMap (`bootstrap/argocd/argocd-rbac-cm-patch.yaml`).

Kubernetes RBAC controls what a subject such as a ServiceAccount may do through
the Kubernetes API. It is configured with Roles and RoleBindings
(`platform/<env>/rbac.yaml`, as in Assignment 2). The two do not overlap:
`reviewer` exists only in Argo CD and has no Kubernetes identity, and `app-viewer`
has no Argo CD account.

With SSO, the local `accounts.reviewer` entry would go, and users would arrive with
groups from the identity provider. `policy.csv` would keep the same permissions
but attach them to a role, with a line mapping the group to it:

```csv
p, role:reviewer, applications, get, dso202/*, allow
p, role:reviewer, projects, get, dso202, allow
p, role:reviewer, logs, get, dso202/*, allow
g, <idp-group>, role:reviewer
```

### Q5 - Why is `argocd app rollback` refused, and why prefer `git revert`?

Rollback moves the cluster to an older revision while Git still says otherwise.
With automated sync on, the two would contradict each other and Argo CD would
apply the bad revision again, so it refuses:

```text
rpc error: code = FailedPrecondition desc = rollback cannot be initiated when auto-sync is enabled
```

The GitOps equivalent is a `git revert` merged by pull request, as in PR #4. It
changes the desired state, and Argo CD follows.

Reverting is better than deleting the bad commit because it keeps the record of
what happened, what undid it and who approved it, which is principle 2. Removing
a commit rewrites shared history: it needs a force-push, breaks other clones, and
can invalidate tags and the revisions recorded in Argo CD history.

### Q6 - One repository, and what is left outside GitOps

**(a)** Advantages of the single repository for this project:

1. One tag pins the chart and the values together, so `v1.2.0` is one complete,
   reviewable definition of staging, and one pull request can change both.
2. A rebuild needs one clone and one `sourceRepos` entry, which keeps Task 9 and
   the project limits simple.

Disadvantages:

1. Access cannot be split. Anyone who can change the chart can also change the
   promotion gate, and a real team would want those reviewed separately.
2. Every commit moves all `main`-tracking Applications to a new revision, even
   when nothing of theirs changed. `platform-staging` went from `7d9b1a4` to
   `4ef2756` although nothing under `platform/staging/` changed in between, which
   makes it harder to see what really affected an Application.

**(b)** Not under GitOps control after the rebuild:

| Item | How a production team usually handles it |
|---|---|
| Bootstrap layer: the cluster, the Argo CD install, the `platform` project | Provision them with infrastructure as code, or manage them from a separate management cluster. |
| Root Application | Create it in the same automated provisioning step, so that it is never applied by a person. |
| Sealing key | Keep it in a managed secrets store or KMS-encrypted backup with restricted, audited access, or replace it with an external secrets manager. |
| Database contents | Take scheduled backups with point-in-time recovery, or use a managed database, and test the restores. |
| Argo CD local passwords | Remove local accounts and sign in through SSO, so that no password has to survive a rebuild. |

## 8. Known gaps

- The rebuild lost the database contents and the `reviewer` password, as expected.
- Drill 4's first evidence run ended with a timeout from the evidence script, not
  from Argo CD. The details are in [`docs/evidence.md`](docs/evidence.md#task-8---drift-pruning-and-project-guardrails).
- The generated `*.sealed.yaml` files carry no comment header, because `kubeseal`
  writes them.
