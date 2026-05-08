# Secret Management: Open Health Stack

This guide explains how to securely manage secrets (passwords, API keys, credentials) in OHS without committing them to Git.

## CRITICAL: Never Commit Secrets to Git

The `.gitignore` file prevents the following from being committed:
- `secrets.yaml`, `secrets-*.yaml`
- `*-secret.yaml`
- `.env`, `.env.local`
- Private keys (`.key`, `.pem`, `.crt`)

**Double-check**: Run `git status` before committing to ensure no secret files are staged.

---

## Secrets Required by OHS

### ohs-credentials Secret

This secret contains all passwords and connection strings:

| Key | Purpose | Example |
|-----|---------|---------|
| `ehrbase-user-password` | EHRbase basic auth password | `MySecurePass123` |
| `ehrbase-db-password` | PostgreSQL password for EHRbase | `DbSecure456` |
| `openfhir-mongo-uri` | MongoDB connection string | `mongodb://openfhir:pass@mongodb-cluster:27017/openfhir` |
| `eos-db-password` | PostgreSQL password for Eos | `EosSecure789` |
| `redis-password` | Redis password (optional) | `RedisPass000` |

---

## Method 1: kubectl create secret (Development)

**Simplest approach for development; NOT recommended for production.**

```bash
# Create secret with literal values
kubectl create secret generic ohs-credentials \
  --from-literal=ehrbase-user-password=YOUR_PASSWORD_HERE \
  --from-literal=ehrbase-db-password=YOUR_DB_PASSWORD \
  --from-literal=openfhir-mongo-uri=mongodb://openfhir:YOUR_PASS@mongodb-cluster:27017/openfhir \
  --from-literal=eos-db-password=YOUR_EOS_PASSWORD \
  -n ohs

# Verify creation
kubectl get secret ohs-credentials -n ohs
kubectl get secret ohs-credentials -n ohs -o jsonpath='{.data}'
```

### Restore from Existing Secret

If you've accidentally deleted the secret:

```bash
# Export secret (only works if it still exists)
kubectl get secret ohs-credentials -n ohs -o yaml > ohs-creds-backup.yaml

# Restore
kubectl apply -f ohs-creds-backup.yaml
```

**Never commit the backup file to Git!**

---

## Method 2: Sealed Secrets (Production)

**Recommended for production.** Encrypts secrets so they can be safely stored in Git.

### Setup (One-time)

```bash
# Install Sealed Secrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system

# Wait for controller to start
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=sealed-secrets \
  -n kube-system --timeout=300s
```

### Create Sealed Secret

```bash
# Create unsecured secret (in memory only)
cat > /tmp/ohs-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ohs-credentials
  namespace: ohs
type: Opaque
stringData:
  ehrbase-user-password: "YOUR_PASSWORD_HERE"
  ehrbase-db-password: "YOUR_DB_PASSWORD"
  openfhir-mongo-uri: "mongodb://openfhir:YOUR_PASS@mongodb-cluster:27017/openfhir"
  eos-db-password: "YOUR_EOS_PASSWORD"
EOF

# Seal (encrypt) the secret
kubeseal -f /tmp/ohs-secret.yaml -w ohs-credentials-sealed.yaml

# Remove unsecured file
rm /tmp/ohs-secret.yaml

# Commit sealed secret to Git
git add ohs-credentials-sealed.yaml
git commit -m "Add sealed secrets"
```

### Deploy with Sealed Secret

```bash
# Apply sealed secret (controller decrypts automatically)
kubectl apply -f ohs-credentials-sealed.yaml

# Verify
kubectl get secret ohs-credentials -n ohs
```

### Backup Sealed Secrets Encryption Key

**CRITICAL**: Back up the sealing key so you can decrypt secrets later.

```bash
# Extract and backup the sealing key
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/status=active \
  -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > sealing-key.crt

kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/status=active \
  -o jsonpath='{.items[0].data.tls\.key}' | base64 -d > sealing-key.key

# Store these files securely (not in Git):
# - Encrypted file backup (e.g., password manager)
# - Physical backup (e.g., secure USB)
# - Cloud storage backup (e.g., AWS Secrets Manager, Azure Key Vault)
```

---

## Method 3: External Secrets Operator (Enterprise)

**For integration with external secret managers (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault).**

### Setup

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system --create-namespace
```

### Example: AWS Secrets Manager

```bash
# Create Secret in AWS (via AWS CLI or console)
aws secretsmanager create-secret \
  --name ohs/credentials \
  --secret-string '{
    "ehrbase-user-password": "...",
    "ehrbase-db-password": "...",
    ...
  }'

# Create ExternalSecret in Kubernetes
cat > external-secret.yaml <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secret-store
  namespace: ohs
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-central-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ohs-credentials
  namespace: ohs
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  target:
    name: ohs-credentials
    creationPolicy: Owner
  data:
  - secretKey: ehrbase-user-password
    remoteRef:
      key: ohs/credentials
      property: ehrbase-user-password
  # Repeat for other secrets...
EOF

kubectl apply -f external-secret.yaml
```

---

## Method 4: SOPS (Ops-Friendly)

**Encrypts YAML files so developers can edit them and store in Git.**

### Setup

```bash
# Install SOPS
brew install sops  # macOS
# or download from https://github.com/mozilla/sops/releases

# Generate encryption key (GPG or AWS KMS)
# Using GPG:
gpg --gen-key  # Create a GPG key

# Configure .sops.yaml
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: secrets.*\.yaml
    pgp: 'YOUR_GPG_KEY_ID'
EOF
```

### Encrypt & Deploy

```bash
# Create plaintext secret file
cat > secrets-example.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ohs-credentials
  namespace: ohs
stringData:
  ehrbase-user-password: "YOUR_PASSWORD"
  ...
EOF

# Encrypt
sops -e secrets-example.yaml > secrets.yaml

# Commit encrypted file
git add secrets.yaml

# Deploy (decrypt on-the-fly)
sops -d secrets.yaml | kubectl apply -f -
```

---

## Rotating Secrets

When you need to change a password (e.g., monthly rotation):

### Using kubectl

```bash
# Update the secret
kubectl patch secret ohs-credentials -n ohs \
  -p '{"data":{"ehrbase-user-password":"'$(echo -n 'NewPassword123' | base64)'"}}'

# Restart affected pods to use new password
kubectl rollout restart deployment/ohs-ehrbase -n ohs

# Verify
kubectl logs ohs-ehrbase-0 -n ohs | grep -i password
```

### Using Sealed Secrets

```bash
# Create new sealed secret with rotated password
kubeseal -f /tmp/new-ohs-secret.yaml -w ohs-credentials-sealed.yaml

# Commit and apply
git add ohs-credentials-sealed.yaml
git commit -m "chore: rotate credentials"
kubectl apply -f ohs-credentials-sealed.yaml

# Restart pods
kubectl rollout restart deployment/ohs-ehrbase -n ohs
```

---

## Password Generation

Generate strong passwords:

```bash
# OpenSSL (secure random)
openssl rand -base64 32

# openssl (shorter)
openssl rand -hex 16

# Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Using pwgen (if installed)
pwgen -s 32 1
```

### Password Requirements

- **Length**: Minimum 16 characters, 32+ recommended
- **Complexity**: Mix of uppercase, lowercase, numbers, special characters
- **Randomness**: Use cryptographically secure generators
- **Uniqueness**: Different password for each service

Example strong passwords:
```
ehrbase:      X7mK9pLq2wN#jH4vR$8sDfG1bZ0eCx
postgres:     9tY5rU2sP@wQ6xL3nM8kJaGf#7dBc1V
mongodb:      HqW8jK3pL$9mN0sR2vT%5xY7cZaGbF1E
```

---

## Auditing Secret Access

Monitor who accesses secrets:

```bash
# Check secret access logs (if audit logging enabled)
kubectl get events -n ohs --sort-by='.lastTimestamp'

# RBAC: Restrict who can read secrets
kubectl auth can-i get secrets --as=user@example.org -n ohs
```

---

## Troubleshooting Secrets

### Secret Not Found Error

```bash
# Verify secret exists
kubectl get secret ohs-credentials -n ohs

# Check secret keys
kubectl get secret ohs-credentials -n ohs -o jsonpath='{.data}'

# Verify pod can access secret
kubectl exec -it ohs-ehrbase-0 -n ohs -- \
  env | grep -i password
```

### Secret Not Being Used

Check environment variables in pod:

```bash
# View pod manifest to verify secret reference
kubectl get pod ohs-ehrbase-0 -n ohs -o yaml | grep -A 5 valueFrom

# Restart pod to reload secret
kubectl delete pod ohs-ehrbase-0 -n ohs
```

### Sealed Secrets Decryption Failed

```bash
# Verify sealing key is installed
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/status=active

# Restore from backup if key was lost
kubectl create secret tls sealed-secrets-key \
  --cert=sealing-key.crt --key=sealing-key.key \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Best Practices

DO:
- Use strong, randomly generated passwords
- Rotate secrets regularly (monthly minimum)
- Store encryption keys securely (separate from secrets)
- Use separate secrets per environment (dev, staging, prod)
- Enable audit logging for secret access
- Back up sealing keys (if using Sealed Secrets)
- Use Kubernetes RBAC to limit secret access

DON'T:
- Commit secrets to Git (use .gitignore)
- Hardcode passwords in code
- Share passwords in Slack, email, or chat
- Use default/example passwords in production
- Reuse passwords across services/environments
- Store backups with production data

---

## References

- **Kubernetes Secrets**: https://kubernetes.io/docs/concepts/configuration/secret/
- **Sealed Secrets**: https://github.com/bitnami-labs/sealed-secrets
- **External Secrets Operator**: https://external-secrets.io/
- **SOPS**: https://github.com/mozilla/sops
- **OWASP Secret Management**: https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html

