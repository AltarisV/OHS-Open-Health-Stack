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
| 9 | openEHRTool-v2 packaging (build Docker image from crs4/openEHRTool-v2) | COMPLETE |
| 10 | EHRsuction -- data export tool | COMPLETE |
| 11 | Data mirroring from BETTER Platform to EHRbase | PENDING |
| 12 | Cohort Explorer (num-portal backend + Angular frontend) | COMPLETE |
| 13 | CSV-to-openEHR bulk import | PENDING |
| 14 | Production hardening (backups, TLS, monitoring, secrets rotation) | PENDING |

## Priority Order

1. **Deploy and verify the core stack** (EHRbase + openFHIR + Eos) -- everything else depends on this
2. **Production hardening** -- backups, HTTPS, monitoring before handling real patient data
3. **openEHRTool-v2** -- deployed; use `build-images.sh` to rebuild if upstream changes
4. **Data mirroring** -- BETTER Platform integration for multi-site data
5. **CSV import** -- remaining data onboarding tooling

## openEHRTool-v2 (Phase 9) -- Implemented

Three subcharts: `openehrtool-backend` (FastAPI, port 5000), `openehrtool-frontend` (Vue3/nginx, port 80), `openehrtool-redis` (Redis 7).

No published Docker images upstream. Build via `build-images.sh` (clones, patches, builds into the target Docker daemon) — see [GETTING_STARTED.md](GETTING_STARTED.md#building-openehrtool-v2) for the commands and the `OPENEHRTOOL_BACKEND_HOSTNAME` details.

Required secret in `ohs-credentials`: `openehrtool-jwt-secret` (set in `.env` before running `create-secret.sh`).

One required upstream patch is applied automatically by `build-images.sh`: `SECRET_KEY` in `backend-fastapi/app/config.py` is changed to read from `OPENEHRTOOL_SECRET_KEY` env var.

## Cohort Explorer -- Deployment Notes

No published Docker images. Build via `build-images.sh` — see [GETTING_STARTED.md](GETTING_STARTED.md#building-and-enabling-cohort-explorer) for the build commands and known build requirements.

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