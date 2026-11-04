# AGENTS.md

Custom bootc/OCI image derived from Bazzite, built with Universal Blue's image-template pattern. There is no application code or test suite; the deliverable is a container image. CI runs on GitHub Actions and publishes to GitHub Container Registry (GHCR).

## Layout

- `Containerfile` — multi-stage build. The `ctx` stage exposes `build_files/`, `config/`, `distrobox/`, and `system_files/` at `/ctx`; `BASE_IMAGE` is pinned to `ghcr.io/ublue-os/bazzite:stable@sha256:...`. Runs `/ctx/build.sh`, then `bootc container lint`.
- `build_files/build.sh` — runs as root in the build container with `set -euxo pipefail`; copies `/ctx/system_files/.` into `/`, then calls the installer scripts.
- `build_files/install-tools.sh` — installs pinned DNF/COPR packages and enables systemd units from `config/tools.yml`.
- `build_files/install-apps.sh` — installs Flatpak apps and pinned AppImages from `config/apps.yml`.
- `build_files/install-distrobox.sh` — validates `config/distrobox.yml` and generates `/etc/distrobox/toschu.ini`.
- `build_files/lib.sh` — shared helpers; downloads a pinned `yq` binary and verifies its SHA256.
- `build_files/yq-version.env` — pinned `yq` version and architecture checksums, shared by `lib.sh` and CI.
- `config/tools.yml` — DNF packages (exact version-release plus repo URL), optional COPR packages, systemd units.
- `config/apps.yml` — Flatpak apps (unpinned, see issue #13) and AppImages (exact version plus SHA256).
- `config/distrobox.yml` — prebuilt Distrobox images (build context, published ref, pinned base, platforms, packages) and containers created on first login.
- `distrobox/` — Containerfiles for prebuilt Distrobox images; each image has its own directory.
- `system_files/` — files copied into the image root; includes `/etc/toschu-os-release`, the `toschu-distrobox-setup` wrapper, and its systemd user service/timer.
- `image-template.env` — image name, registry, owner, tag; auto-loaded by the `Justfile`.
- `.github/workflows/build.yml` — bootc image build and push. Every `uses:` is pinned to a full commit SHA.
- `.github/workflows/distrobox.yml` — YAML-driven Distrobox image matrix build and push.
- `.github/scripts/distrobox-matrix.py` — validates `config/distrobox.yml` and emits the GitHub Actions matrix.
- `renovate.json` — Renovate config; updates action SHAs, base-image digests, pinned DNF packages, AppImage versions, and Distrobox base-image digests.

## Commands

```bash
just build          # podman build -> toschu-os:stable
just build-root     # same, via sudo podman, usable by bootc
just lint           # shellcheck every *.sh plus the toschu-distrobox-setup wrapper
just format         # shfmt --write every *.sh plus the toschu-distrobox-setup wrapper
podman login ghcr.io -u LmV4corbeau   # required before `just push`
just push           # push stable + latest to ghcr.io/lmv4corbeau/toschu-os
```

CI builds on pull requests and pushes `stable` + `latest` on `main`. It does not run `just lint`; the Distrobox workflow runs a smoke test for its images. Run `just lint` locally before committing. There is no single-test command.

Local rebase test:

```bash
just build-root
sudo bootc switch --transport containers-storage localhost/toschu-os:stable
```

Published image:

```bash
sudo bootc switch ghcr.io/lmv4corbeau/toschu-os:stable
# fallback for unsigned images:
sudo rpm-ostree rebase ostree-unverified-registry:docker://ghcr.io/lmv4corbeau/toschu-os:stable
```

## GitHub Actions

- Runs on `ubuntu-24.04` with Docker Buildx (`docker/build-push-action`), not Buildah or Podman.
- Actions are pinned to full commit SHAs with a version comment (e.g. `# v4.4.0`). Do not replace them with moving tags like `@v4`; Renovate updates the SHA and comment.
- Uses the built-in `GITHUB_TOKEN`; workflow permissions are `contents: read` and `packages: write`. No PAT secret is needed in CI.
- PRs build only; pushes to `main` publish `stable` and `latest` to GHCR.
- `.github/workflows/distrobox.yml` builds the images from `config/distrobox.yml` with a dynamic matrix. PRs build `linux/amd64` and run a smoke test; `main` pushes every configured platform to `ghcr.io/lmv4corbeau/toschu-os-distrobox/<name>:<tag>`. An empty image list is valid and skips the build job.
- GHCR paths must be lowercase: the account is `LmV4corbeau`, but the registry owner is `lmv4corbeau`.
- The workflow triggers on pushes to `main` only when `Containerfile`, `build_files/**`, `config/**`, `system_files/**`, `image-template.env`, or the workflow itself changes; use `workflow_dispatch` for other rebuilds.
- After the first push, the GHCR package may be private; set its visibility to public in the repository's **Packages** settings if needed.

## Build gotchas

- `dnf5` is available in Bazzite; RPM Fusion is already enabled.
- Add packages to `config/tools.yml`, not directly to `build_files/build.sh`. Every DNF package needs `name`, exact `version` (version-release), and `repo`.
- `repo` must point at the repository's `repodata/` directory (Renovate's `rpm` datasource reads `repomd.xml` from it). Use the `updates` repo when it carries the package, otherwise the `releases` repo.
- Enable COPRs only for the install, then disable them again (`dnf5 copr disable ...`).
- Flatpak apps are intentionally unpinned until issue #13 is resolved. AppImages require `version` and `sha256`; Renovate updates the version but not the checksum.
- Prebuilt Distrobox images live in `config/distrobox.yml`. Each image needs a `context` under `distrobox/` containing a `Containerfile`, a `ref` under `ghcr.io/lmv4corbeau/toschu-os-distrobox/<name>:`, a `base` with both a tag and a digest, at least one `linux/amd64`/`linux/arm64` platform that the base actually supports, and an optional `packages` list passed as the `PACKAGES` build arg. An empty `images: {}` and `containers: {}` is valid.
- `build_files/install-distrobox.sh` writes `/etc/distrobox/toschu.ini`; never modify Bazzite's `/etc/distrobox/distrobox.ini`. Distrobox is rootless and per-user, so the setup runs from a systemd user timer on first login and daily to pick up newer images, not from a system-wide service.
- `build_files/lib.sh` downloads `yq` at build time and verifies its SHA256. `build_files/yq-version.env` is shared with the Distrobox workflow; update `YQ_VERSION` and both architecture checksums together.
- The `RUN --mount=type=bind,from=ctx` stage is required because `build_files/`, `config/`, `distrobox/`, and `system_files/` must not be copied into the final image.
- `bootc container lint` must pass; do not remove it.
- Images are unsigned. Do not add signing steps without providing cosign keys as secrets, and never commit `cosign.key`.
- Keep `IMAGE_NAME`, `IMAGE_OWNER`, `IMAGE_REGISTRY`, and `DEFAULT_TAG` in sync between `image-template.env` and the `env:` block in `.github/workflows/build.yml`; keep the repository URLs in `Containerfile` and `system_files/etc/toschu-os-release` in sync with the GitHub repo.
- Keep the `BASE_IMAGE` tag (`:stable`) alongside its digest so Renovate knows which update channel to follow. Do not drop the digest or replace it with a plain tag.
- `README.md` is user-facing and written in English; update it when changing image name, registry, or tags.
- `../homelab` and `../heimdall` are separate repositories; do not import their Ansible conventions here.
