# toschu-os

Eigenes bootc-/OCI-Image auf Basis von **Bazzite stable** (KDE, AMD/Intel). Das Image wird über ein `Containerfile` abgeleitet und mit Podman lokal oder über GitHub Actions gebaut und nach GitHub Container Registry (GHCR) veröffentlicht.

- Repository: <https://github.com/LmV4corbeau/toschu-os>
- Image: `ghcr.io/lmv4corbeau/toschu-os:stable`
- Basis: `ghcr.io/ublue-os/bazzite:stable`

## Voraussetzungen

- Ein bootc-/Fedora-Atomic-System (z. B. Bazzite) zum Testen
- `podman`, `just`, `git`
- Ein GitHub-Konto und ein Personal Access Token mit `write:packages` (für lokale Pushes nach GHCR)

## Lokal bauen

```bash
just build
```

Für einen Rebase auf das lokal gebaute Image muss es in der rootful Podman-Storage liegen:

```bash
just build-root
sudo bootc switch --transport containers-storage localhost/toschu-os:stable
sudo reboot
```

Falls `bootc switch` nicht verfügbar ist:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:docker://ghcr.io/lmv4corbeau/toschu-os:stable
```

Rollback:

```bash
sudo bootc rollback
# oder
sudo rpm-ostree rollback
```

## Nach GHCR pushen

Das Image heißt `ghcr.io/lmv4corbeau/toschu-os` (Owner und Image-Name müssen klein geschrieben sein).

```bash
podman login ghcr.io -u LmV4corbeau
just build
just push
```

Das Login braucht ein PAT mit `write:packages` (classic) bzw. passende Package-Berechtigung bei fine-grained Tokens. Das automatische `GITHUB_TOKEN` funktioniert nur innerhalb von GitHub Actions.

## GitHub Actions

Der Workflow liegt in `.github/workflows/build.yml`.

- Läuft bei Pushes auf `main` (nur bei Änderungen an `Containerfile`, `build_files/`, `system_files/`, `image-template.env` oder dem Workflow selbst), bei Pull Requests sowie manuell über **Actions → Build and push bootc image → Run workflow**.
- Baut das Image mit Docker Buildx und pusht `stable` und `latest` nach GHCR.
- Nutzt das eingebaute `GITHUB_TOKEN`; zusätzliche Secrets sind nicht nötig. Die Workflow-Permissions `contents: read` und `packages: write` sind gesetzt.

Falls das Image nach dem ersten Push nicht öffentlich ist, im Repository unter **Packages** die Sichtbarkeit des Pakets auf public stellen.

## Anpassungen

- `build_files/build.sh` – Pakete installieren, systemd-Units aktivieren, Aufräumarbeiten
- `system_files/` – Dateien, die nach `/` kopiert werden
- `Containerfile` – Basisimage und Build-Schritte
- `image-template.env` – lokaler Image-Name, Registry und Tag

Die Basis lässt sich z. B. auf `bazzite-nvidia-open:stable` oder `bazzite-deck:stable` ändern:

```dockerfile
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite-nvidia-open:stable
```

## Registry

GHCR ist für öffentliche Images kostenlos. Pull des veröffentlichten Images:

```bash
podman pull ghcr.io/lmv4corbeau/toschu-os:stable
```

## Sicherheit

- Images sind derzeit **nicht signiert**.
- `cosign.key` und Registry-Tokens niemals committen.
- Für öffentliche Repositories ist eine FLOSS-Lizenz erforderlich.
