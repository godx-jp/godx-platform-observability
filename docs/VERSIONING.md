# Versioning policy

This repo ships **opinionated configuration** for upstream observability components. It is itself versioned with **[SemVer 2.0.0](https://semver.org/)**.

## Version channels

| Channel | Convention | Use |
|---------|------------|-----|
| **Release** | `vX.Y.Z` git tag | Pin in consumer projects |
| **Pre-release** | `vX.Y.Z-rc.N` | Validate before promotion |
| **Main** | `main` branch | Bleeding edge — don't pin in prod |

`VERSION` file at the repo root is the source of truth; `CHANGELOG.md` documents every release.

## What's covered by SemVer

| Surface | SemVer-tracked? |
|---------|-----------------|
| Compose file paths (`compose/docker-compose.yml`) | ✅ |
| Config file paths (`config/**`) | ✅ |
| Env var names and defaults (`.env.example`) | ✅ |
| Network name default (`observability`) | ✅ |
| Service container names (`obs-*`) | ✅ |
| Grafana datasource UIDs (`loki`, `prometheus`, `tempo`) | ✅ |
| Upstream image **pins** (e.g. Loki `3.3.0`) | ⚠ minor bumps allowed within compatible range |

## What changes mean

| Change | Bump |
|--------|------|
| Add a new optional service / env var with a default | **PATCH** or **MINOR** |
| Add a new compose flavour | **MINOR** |
| Rename an env var, network, container, or service | **MAJOR** |
| Remove a config file or directory consumers may bind-mount | **MAJOR** |
| Major upstream version bump that requires consumer migration (e.g. Loki 3 → 4) | **MAJOR** |
| Minor upstream version bump with no consumer-visible change | **PATCH** |
| Security fix in pinned upstream image | **PATCH** |

## Consumer compatibility matrix

| Consumer pins | Compatible release |
|---------------|--------------------|
| `v0.1.x` | `v0.1.*` (this) |
| `v0.x.y` | within same MINOR for breaking |
| `v1.x.y` and above | guaranteed backwards-compatible within MAJOR |

Until `v1.0.0`, MINOR bumps may break. Pin to **exact** tag in production.

## Upgrade flow (consumer)

```bash
# 1. Read the CHANGELOG diff
git -C vendor/observability log v0.1.0..v0.2.0 -- CHANGELOG.md

# 2. Bump
cd vendor/observability && git checkout v0.2.0 && cd ../..

# 3. Validate
docker compose config -q
make health

# 4. Roll out
```

## Release flow (maintainer)

```bash
# 1. Update VERSION + CHANGELOG
echo "0.2.0" > VERSION
$EDITOR CHANGELOG.md

# 2. Validate
make validate

# 3. Tag + push
git commit -am "Release v0.2.0"
git tag -a v0.2.0 -m "v0.2.0"
git push origin main v0.2.0
```

CI publishes the tag; consumers `git pull` + bump.
