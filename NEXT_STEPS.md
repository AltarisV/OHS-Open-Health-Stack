# Next Steps & Roadmap

## Immediate: Complete Deployment

- [ ] Replace all `CHANGE_ME` placeholders in `values.yaml`
- [ ] Create `ohs-credentials` secret (see [SECRETS.md](SECRETS.md))
- [ ] Install operators (CloudNativePG, MongoDB -- see [DEPLOYMENT.md](DEPLOYMENT.md))
- [ ] `helm install ohs . -f values.yaml -n ohs`
- [ ] Follow [VERIFICATION.md](VERIFICATION.md) to confirm all services are healthy

## Roadmap

| Phase | Title | Status |
|-------|-------|--------|
| 1-8 | Repository foundation, operators, core components, docs | COMPLETE |
| 9 | openEHRTool-v2 packaging (build Docker image from crs4/openEHRTool-v2) | PENDING |
| 10 | EHRsuction -- data export tool | PENDING |
| 11 | Data mirroring from BETTER Platform to EHRbase | PENDING |
| 12 | Cohort Explorer (num-portal backend + Angular frontend) | IN PROGRESS |
| 13 | CSV-to-openEHR bulk import | PENDING |
| 14 | Production hardening (backups, TLS, monitoring, secrets rotation) | PENDING |

## Priority Order

1. **Deploy and verify the core stack** (EHRbase + openFHIR + Eos) -- everything else depends on this
2. **Production hardening** -- backups, HTTPS, monitoring before handling real patient data
3. **openEHRTool-v2** -- needs custom Docker image built from upstream source (`packaging/openEHRTool-v2/`)
4. **Data mirroring** -- BETTER Platform integration for multi-site data
5. **Cohort Explorer + CSV import** -- analytics and data onboarding tooling

## openEHRTool-v2 (Phase 9) -- Key Notes

No published Docker image exists upstream. Build steps:

```bash
git clone https://github.com/crs4/openEHRTool-v2.git packaging/openEHRTool-v2/src
# Write multi-stage Dockerfile: Node 22 (Vue build) + Python 3.11-slim (FastAPI runtime)
docker build -t your-registry/opehrtool-v2:0.1.0 packaging/openEHRTool-v2/
docker push your-registry/opehrtool-v2:0.1.0
# Re-enable the subchart in values.yaml and helm upgrade
```

## Cohort Explorer (Phase 12) -- Key Notes

No published Docker images. Build into minikube's Docker daemon for local dev:

```bash
eval $(minikube docker-env)

git clone https://github.com/highmed/cohort-explorer-backend
docker build -t cohort-explorer-backend:local cohort-explorer-backend/

git clone https://github.com/highmed/cohort-explorer-frontend
docker build --build-arg ENVIRONMENT=deploy \
  -t cohort-explorer-frontend:local cohort-explorer-frontend/
```

**Prerequisites** (beyond the core stack):
- **Keycloak** (required — the backend uses it for JWT auth and user management):
  - Realm `crr` and both clients (`num-portal`, `num-portal-webapp`) are created
    **automatically** on first startup via `--import-realm` (see `charts/keycloak/templates/configmap-realm.yaml`).
    Import is idempotent — if the realm already exists it is skipped.
- Add 6 keys to `ohs-credentials`:
  `keycloak-admin-password`, `keycloak-db-password`,
  `numportal-db-password`, `numportal-keycloak-secret`,
  `numportal-pseudonymity-secret`, `ehrbase-admin-password`
- Enable the databases: `postgres.numportal.enabled: true`, `postgres.keycloak.enabled: true`
- Enable services: `keycloak.enabled: true`, `cohort-explorer-backend.enabled: true`, `cohort-explorer-frontend.enabled: true`
- Set `cohort-explorer-frontend.config.api.baseUrl` to the backend's external URL