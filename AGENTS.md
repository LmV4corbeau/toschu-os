# AGENTS.md

Custom bootc/OCI image derived from Bazzite, built with Universal Blue's image-template pattern. There is no application code or test suite; the deliverable is a container image. CI runs on GitHub Actions and publishes to GitHub Container Registry (GHCR).

## Layout

- `Containerfile` — multi-stage build. The `ctx` stage exposes `build_files/` and `system_files/` at `/ctx`; `BASE_IMAGE` defaults to `ghcr.io/ublue-os/bazzite:stable`. Runs `/ctx/build.sh`, then `bootc container lint`.
- `build_files/build.sh` — runs as root in the build container with `set -euxo pipefail`; installs packages and copies `/ctx/system_files/.` into `/`.
- `system_files/` — files copied into the image root; includes `/etc/toschu-os-release`.
- `image-template.env` — image name, registry, owner, tag; auto-loaded by the `Justfile`.
- `.github/workflows/build.yml` — GitHub Actions build and push.

## Commands

```bash
just build          # podman build -> toschu-os:stable
just build-root     # same, via sudo podman, usable by bootc
just lint           # shellcheck every *.sh (recursive; also build.sh)
just format         # shfmt --write every *.sh
podman login ghcr.io -u LmV4corbeau   # required before `just push`
just push           # push stable + latest to ghcr.io/lmv4corbeau/toschu-os
```

CI builds on pull requests and pushes `stable` + `latest` on `main`, but it does not run lint or tests. Run `just lint` locally before committing. There is no single-test command.

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
- Uses the built-in `GITHUB_TOKEN`; workflow permissions are `contents: read` and `packages: write`. No PAT secret is needed in CI.
- PRs build only; pushes to `main` publish `stable` and `latest` to GHCR.
- GHCR paths must be lowercase: the account is `LmV4corbeau`, but the registry owner is `lmv4corbeau`.
- The workflow triggers on pushes to `main` only when `Containerfile`, `build_files/**`, `system_files/**`, `image-template.env`, or the workflow itself changes; use `workflow_dispatch` for other rebuilds.
- After the first push, the GHCR package may be private; set its visibility to public in the repository's **Packages** settings if needed.

## Build gotchas

- `dnf5` is available in Bazzite; RPM Fusion is already enabled.
- Enable COPRs only for the install, then disable them again (`dnf5 copr disable ...`).
- The `RUN --mount=type=bind,from=ctx` stage is required because `build.sh` and `system_files/` must not be copied into the final image.
- `bootc container lint` must pass; do not remove it.
- Images are unsigned. Do not add signing steps without providing cosign keys as secrets, and never commit `cosign.key`.
- Keep `IMAGE_NAME`, `IMAGE_OWNER`, `IMAGE_REGISTRY`, and `DEFAULT_TAG` in sync between `image-template.env` and the `env:` block in `.github/workflows/build.yml`; keep the repository URLs in `Containerfile` and `system_files/etc/toschu-os-release` in sync with the GitHub repo.
- `README.md` is user-facing and written in German; update it when changing image name, registry, or tags.
- `../homelab` and `../heimdall` are separate repositories; do not import their Ansible conventions here.
