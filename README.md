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

- Runs on pushes to `main` (only when `Containerfile`, `build_files/`, `system_files/`, `image-template.env`, or the workflow itself changes), on pull requests, and manually via **Actions → Build and push bootc image → Run workflow**.
- Builds the image with Docker Buildx and pushes `stable` and `latest` to GHCR.
- Uses the built-in `GITHUB_TOKEN`; no additional secrets are required. The workflow permissions `contents: read` and `packages: write` are set.

If the image is not public after the first push, set the package visibility to public under **Packages** in the repository.

## Customization

- `build_files/build.sh` – install packages, enable systemd units, clean up
- `system_files/` – files copied into `/`
- `Containerfile` – base image and build steps
- `image-template.env` – local image name, registry, and tag

The base image is pinned by tag and digest in the `Containerfile`. When switching the base, add a digest as well:

```dockerfile
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite-nvidia-open:stable@sha256:...
```

## Updates

The base image and GitHub Actions are pinned by digest and commit SHA respectively. Renovate (`renovate.json`) proposes updates as pull requests.

## Registry

GHCR is free for public images. Pull the published image:

```bash
podman pull ghcr.io/lmv4corbeau/toschu-os:stable
```

## Security

- Images are currently **unsigned**.
- Never commit `cosign.key` or registry tokens.
- Public repositories require a FLOSS license.
