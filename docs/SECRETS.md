# Secret Management: Open Health Stack

## Secrets Required

A deployment needs **seven** secrets, not one. `ohs-credentials` holds the application
passwords; the database operators read their credentials from separate secrets of their own,
and CloudNativePG requires the `kubernetes.io/basic-auth` type for managed roles.

### `ohs-credentials`

| Key | Purpose |
|-----|----------|
| `ehrbase-user-password` | EHRbase basic auth password |
| `ehrbase-db-password` | PostgreSQL password for EHRbase |
| `ehrbase-admin-password` | EHRbase admin API password (used by cohort-explorer-backend) |
| `openfhir-mongo-uri` | Full MongoDB connection string including password |
| `eos-db-password` | PostgreSQL password for Eos |
| `redis-password` | Redis password (not currently used - openEHRTool-v2 Redis runs without auth) |
| `openehrtool-jwt-secret` | JWT signing secret for openEHRTool-v2 FastAPI backend |
| `keycloak-admin-password` | Keycloak admin console password |
| `keycloak-research-password` | Password for the portal user `research`; empty means Keycloak assigns a random one |
| `numportal-keycloak-secret` | Client secret for the `num-portal` Keycloak client (auto-imported into realm `crr`) |
| `numportal-pseudonymity-secret` | Random secret used by the cohort-explorer-backend for pseudonymity masking |

`keycloak-db-password` and `numportal-db-password` are **not** keys of this secret. Those
roles are managed by CloudNativePG and read from the basic-auth secrets below.

### Database secrets

| Secret | Type | Contents |
|--------|------|----------|
| `postgres-cluster-app` | `kubernetes.io/basic-auth` | `ehrbase` / EHRbase DB password - the CNPG application user |
| `postgres-eos-user-secret` | `kubernetes.io/basic-auth` | `eos` / Eos DB password |
| `postgres-keycloak-user-secret` | `kubernetes.io/basic-auth` | `keycloak` / Keycloak DB password |
| `postgres-numportal-user-secret` | `kubernetes.io/basic-auth` | `numportal` / num-portal DB password |
| `mongodb-root-password` | `Opaque`, key `password` | MongoDB root user |
| `mongodb-openfhir-password` | `Opaque`, key `password` | MongoDB user for openFHIR |

> The password inside `openfhir-mongo-uri` **must exactly match** `mongodb-openfhir-password`,
> and `postgres-cluster-app` must match `ehrbase-db-password`. Mismatches surface as
> authentication errors at pod start, not at install time.

---

## Method 1: scripts/create-secret.sh (recommended)

All seven secrets come from one `.env` file, so the values cannot drift apart:

```bash
cp .env.example .env
# fill in every value, then:
bash scripts/create-secret.sh
```

The script is idempotent - it applies with `--dry-run=client -o yaml | kubectl apply -f -`,
so re-running it updates the secrets in place. `scripts/local-up.sh` calls it, and generates
a `.env` with random credentials when none exists.

Creating them by hand is possible but has to cover all seven; the script is the
maintained list. Generate individual values with `openssl rand -base64 32`.

---

## Method 2: Sealed Secrets (Production - GitOps-friendly)

Encrypts secrets so they can be safely committed to Git:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Create the plain secret, seal it, delete the plain file
kubectl create secret generic ohs-credentials -n ohs --dry-run=client \
  --from-literal=ehrbase-user-password=... -o yaml | kubeseal -w ohs-credentials-sealed.yaml

git add ohs-credentials-sealed.yaml  # safe to commit
```

**Back up the sealing key** - without it you cannot decrypt:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/status=active \
  -o jsonpath='{.items[0].data.tls\.key}' | base64 -d > sealing-key.key
```

---

## Method 3: External Secrets Operator (Enterprise)

For HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, etc.
See [external-secrets.io](https://external-secrets.io/) for setup.

---

## Method 4: SOPS

Encrypts YAML files in-place for Git storage.
See [github.com/mozilla/sops](https://github.com/mozilla/sops).

---

## Rotating Secrets

```bash
kubectl patch secret ohs-credentials -n ohs \
  -p '{"data":{"ehrbase-user-password":"'$(echo -n 'NewPassword' | base64)'"}}'
kubectl rollout restart deployment/ohs-ehrbase -n ohs
```

---

## Best Practices

- Never commit secrets or secret files to Git (`.gitignore` covers common patterns)
- Use a different password per service and per environment
- Rotate credentials regularly (quarterly minimum for production)
- Use RBAC to restrict which pods and users can read secrets
