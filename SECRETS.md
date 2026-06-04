# Secret Management: Open Health Stack

## Secrets Required

The `ohs-credentials` secret must be created before `helm install`:

| Key | Purpose |
|-----|----------|
| `ehrbase-user-password` | EHRbase basic auth password |
| `ehrbase-db-password` | PostgreSQL password for EHRbase |
| `ehrbase-admin-password` | EHRbase admin API password (used by cohort-explorer-backend) |
| `openfhir-mongo-uri` | Full MongoDB connection string including password |
| `eos-db-password` | PostgreSQL password for Eos |
| `redis-password` | Redis password (not currently used — openEHRTool-v2 Redis runs without auth) |
| `openehrtool-jwt-secret` | JWT signing secret for openEHRTool-v2 FastAPI backend |
| `keycloak-admin-password` | Keycloak admin console password |
| `keycloak-db-password` | PostgreSQL password for Keycloak |
| `numportal-db-password` | PostgreSQL password for the cohort-explorer-backend |
| `numportal-keycloak-secret` | Client secret for the `num-portal` Keycloak client (auto-imported into realm `crr`) |
| `numportal-pseudonymity-secret` | Random secret used by the cohort-explorer-backend for pseudonymity masking |

> The password in `openfhir-mongo-uri` **must exactly match** `mongodb.openfhir.userPassword` in your values file.

---

## Method 1: kubectl (Development)

```bash
kubectl create secret generic ohs-credentials --namespace ohs \
  --from-literal=ehrbase-user-password=YOUR_SECURE_PASSWORD \
  --from-literal=ehrbase-db-password=YOUR_DB_PASSWORD \
  --from-literal=ehrbase-admin-password=YOUR_ADMIN_PASSWORD \
  --from-literal=openfhir-mongo-uri='mongodb://openfhir:MONGO_PASS@mongodb-cluster-svc.ohs.svc.cluster.local:27017/openfhir' \
  --from-literal=eos-db-password=YOUR_EOS_PASSWORD \
  --from-literal=redis-password=YOUR_REDIS_PASSWORD \
  --from-literal=keycloak-admin-password=YOUR_KC_ADMIN_PASSWORD \
  --from-literal=keycloak-db-password=YOUR_KC_DB_PASSWORD \
  --from-literal=numportal-db-password=YOUR_NUMPORTAL_DB_PASSWORD \
  --from-literal=numportal-keycloak-secret=$(openssl rand -base64 32) \
  --from-literal=numportal-pseudonymity-secret=$(openssl rand -base64 32)
```

Generate a strong password: `openssl rand -base64 32`

---

## Method 2: Sealed Secrets (Production — GitOps-friendly)

Encrypts secrets so they can be safely committed to Git:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Create the plain secret, seal it, delete the plain file
kubectl create secret generic ohs-credentials -n ohs --dry-run=client \
  --from-literal=ehrbase-user-password=... -o yaml | kubeseal -w ohs-credentials-sealed.yaml

git add ohs-credentials-sealed.yaml  # safe to commit
```

**Back up the sealing key** — without it you cannot decrypt:

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
