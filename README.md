# toschu-os

Custom bootc/OCI image based on **Bazzite stable** (KDE, AMD/Intel). The image is derived from a `Containerfile` and built locally with Podman or via GitHub Actions, then published to the GitHub Container Registry (GHCR).

- Repository: <https://github.com/LmV4corbeau/toschu-os>
- Image: `ghcr.io/lmv4corbeau/toschu-os:stable`
- Base: `ghcr.io/ublue-os/bazzite:stable`

## Prerequisites

- A bootc/Fedora Atomic system (e.g. Bazzite) for testing
- `podman`, `just`, `git`
- A GitHub account and a personal access token with `write:packages` (for local pushes to GHCR)

## Build locally

```bash
just build
```

To rebase onto the locally built image, it must be in rootful Podman storage:

```bash
just build-root
sudo bootc switch --transport containers-storage localhost/toschu-os:stable
sudo reboot
```

If `bootc switch` is unavailable:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:docker://ghcr.io/lmv4corbeau/toschu-os:stable
```

Rollback:

```bash
sudo bootc rollback
# or
sudo rpm-ostree rollback
```

## Push to GHCR

The image is named `ghcr.io/lmv4corbeau/toschu-os` (owner and image name must be lowercase).

```bash
podman login ghcr.io -u LmV4corbeau
just build
just push
```

The login requires a PAT with `write:packages` (classic) or the corresponding package permission for fine-grained tokens. The automatic `GITHUB_TOKEN` only works inside GitHub Actions.

## GitHub Actions

The workflow lives in `.github/workflows/build.yml`.

- Runs on pushes to `main` (only when `Containerfile`, `build_files/`, `config/`, `system_files/`, `image-template.env`, or the workflow itself changes), on pull requests, and manually via **Actions → Build and push bootc image → Run workflow**.
- Builds the image with Docker Buildx and pushes `stable` and `latest` to GHCR.
- Uses the built-in `GITHUB_TOKEN`; no additional secrets are required. The workflow permissions `contents: read` and `packages: write` are set.

If the image is not public after the first push, set the package visibility to public under **Packages** in the repository.

## Customization

- `config/tools.yml` – pinned DNF packages, optional COPR packages, and systemd units
- `config/apps.yml` – Flatpak apps and pinned AppImages
- `build_files/` – build scripts that read the configuration files
- `system_files/` – files copied into `/`
- `Containerfile` – base image and build steps
- `image-template.env` – local image name, registry, and tag

The base image is pinned by tag and digest in the `Containerfile`. When switching the base, add a digest as well:

```dockerfile
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite-nvidia-open:stable@sha256:...
```

### DNF packages and systemd units

Every DNF package is pinned to an exact version-release in `config/tools.yml`:

```yaml
dnf:
  packages:
    - name: tmux
      version: "3.7c-1.fc45"
      repo: https://mirrors.kernel.org/fedora/releases/45/Everything/x86_64/os/repodata/

systemd:
  enable:
    - podman.socket
```

`repo` points to the `repodata/` directory that currently contains the pinned version; Renovate uses it to look up newer versions. COPR packages can be added under `copr:`. The repository is enabled only for the install and disabled again afterwards.

If a pinned version disappears from the repository before Renovate updates it, the build fails. That is intentional so the image never silently drifts.

### Flatpak apps and AppImages

`config/apps.yml` installs Flatpak apps by ID from the configured remote. Flatpak apps are **not version-pinned yet**; see [issue #13](https://github.com/LmV4corbeau/toschu-os/issues/13).

AppImages are pinned to an exact version and verified by SHA256:

```yaml
appimage:
  - name: example-tool
    repo: owner/repo
    version: "1.2.3"
    url: https://github.com/owner/repo/releases/download/v{{version}}/Example-{{version}}-x86_64.AppImage
    sha256: "..."
```

AppImages are installed to `/usr/local/bin`. Renovate updates `version`, but it cannot calculate the new SHA256; update `sha256` manually in the pull request.

## Updates

The base image, GitHub Actions, pinned DNF packages (`rpm` datasource), and AppImages (`github-releases` datasource) are updated by Renovate (`renovate.json`). Flatpak apps are not pinned yet (see issue #13).

## Registry

GHCR is free for public images. Pull the published image:

```bash
podman pull ghcr.io/lmv4corbeau/toschu-os:stable
```

## Security

- Images are currently **unsigned**.
- Never commit `cosign.key` or registry tokens.
- Public repositories require a FLOSS license.
