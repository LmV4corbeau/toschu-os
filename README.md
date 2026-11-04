# toschu-os

Custom bootc/OCI image based on **Bazzite stable** (KDE, AMD/Intel). The image is derived from a `Containerfile` and built locally with Podman or via GitHub Actions, then published to the GitHub Container Registry (GHCR).

- Repository: <https://github.com/LmV4corbeau/toschu-os>
- Image: `ghcr.io/lmv4corbeau/toschu-os:stable`
- Base: `ghcr.io/ublue-os/bazzite:stable`

## Prerequisites

- A bootc/Fedora Atomic system (e.g. Bazzite) for testing
- `podman`, `just`, `git`, and `distrobox` (for local container tests)
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
- `.github/workflows/distrobox.yml` builds the prebuilt Distrobox images defined in `config/distrobox.yml`. It builds and smoke-tests `linux/amd64` on pull requests and pushes all configured platforms to GHCR on `main`.

If the image is not public after the first push, set the package visibility to public under **Packages** in the repository.

## Customization

- `config/tools.yml` – pinned DNF packages, optional COPR packages, and systemd units
- `config/apps.yml` – Flatpak apps and pinned AppImages
- `config/distrobox.yml` – prebuilt Distrobox images and the containers created from them
- `build_files/` – build scripts that read the configuration files
- `distrobox/` – Containerfiles for the prebuilt Distrobox images
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

## Prebuilt Distrobox images

`config/distrobox.yml` defines the Distrobox images that are built in CI and the containers that are created from them on first login:

```yaml
images:
  example:
    context: distrobox/example
    ref: ghcr.io/lmv4corbeau/toschu-os-distrobox/example:latest
    base: ghcr.io/ublue-os/fedora-toolbox:latest@sha256:...
    platforms:
      - linux/amd64
    packages:
      - git
      - zsh

containers:
  example:
    image: example
    pull: true
    nvidia: false
    init: false
    replace: false
    exported_apps: []
    exported_bins: []
```

- `context` is a directory under `distrobox/` containing a `Containerfile`. `distrobox/example/Containerfile` is a template; adapt the package-install block for non-Fedora bases.
- `ref` is the image published to GHCR. It must use the `ghcr.io/lmv4corbeau/toschu-os-distrobox/` prefix and the same name as the entry.
- `base` is passed to the Containerfile as `BASE_IMAGE` and must keep both a tag and a digest. Renovate updates the digest.
- `platforms` must match the architectures supported by `base`. The pinned UBlue toolbox images used by the example are `linux/amd64` only.
- `packages` is passed to the Containerfile as the `PACKAGES` build argument.
- `containers` is written to `/etc/distrobox/toschu.ini` at bootc build time. `image` is either an `images` key or a full image reference.
- `replace: true` recreates an existing container when the manifest changes. Without it, existing containers are left alone.

The workflow `.github/workflows/distrobox.yml` builds and pushes images on `main`, and builds the `linux/amd64` image plus a smoke test on pull requests. An empty `images: {}` is valid: no images are built and the workflow still succeeds.

The bootc image enables the `toschu-distrobox-setup.timer` systemd user timer. On first login it runs `distrobox assemble create --file /etc/distrobox/toschu.ini`, which pulls the prebuilt images and creates the containers. The timer is rootless and per-user; a hash marker in `~/.local/state/toschu-os/` prevents repeated work until the manifest changes. If the first run fails (for example, because the network is not ready), the timer retries every six hours.

To test an image locally:

```bash
podman build \
  --build-arg BASE_IMAGE=ghcr.io/ublue-os/fedora-toolbox:latest@sha256:... \
  --build-arg PACKAGES="git zsh" \
  --file distrobox/example/Containerfile \
  --tag toschu-os-distrobox/example:latest \
  distrobox/example

podman run --rm -it toschu-os-distrobox/example:latest /bin/bash
```

After rebasing onto the bootc image, trigger the setup manually with:

```bash
systemctl --user start toschu-distrobox-setup.service
systemctl --user status toschu-distrobox-setup.service
```

To enable the example, replace `images: {}` and `containers: {}` in `config/distrobox.yml` with the uncommented blocks.

## Updates

The base image, GitHub Actions, pinned DNF packages (`rpm` datasource), AppImages (`github-releases` datasource), and Distrobox base images (`docker` datasource) are updated by Renovate (`renovate.json`). Flatpak apps are not pinned yet (see issue #13).

## Registry

GHCR is free for public images. Pull the published image:

```bash
podman pull ghcr.io/lmv4corbeau/toschu-os:stable
```

Prebuilt Distrobox images are published under `ghcr.io/lmv4corbeau/toschu-os-distrobox/<name>:<tag>`.

## Security

- Images are currently **unsigned**, including the prebuilt Distrobox images.
- Never commit `cosign.key` or registry tokens.
- Public repositories require a FLOSS license.
