#!/usr/bin/env python3
"""Build a GitHub Actions matrix from config/distrobox.yml.

The workflow converts the YAML file to JSON with the pinned yq binary and
passes the result to this script. Keeping the validation here means a broken
image definition fails before any build starts.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

PREFIX = "ghcr.io/lmv4corbeau/toschu-os-distrobox/"
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
CONTEXT_RE = re.compile(r"^distrobox/[A-Za-z0-9][A-Za-z0-9._/-]*$")
REF_RE = re.compile(
    r"^ghcr\.io/lmv4corbeau/toschu-os-distrobox/"
    r"[a-z0-9][a-z0-9._-]*:[A-Za-z0-9_][A-Za-z0-9._-]*$"
)
BASE_RE = re.compile(r"^[^\s@]+:[^@\s]+@sha256:[0-9a-f]{64}$")
PACKAGE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+:-]*$")
IMAGE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:@-]*$")
ITEM_RE = re.compile(r"^[A-Za-z0-9._/~+@:%-]+$")
PLATFORMS = {"linux/amd64", "linux/arm64"}


def fail(message: str) -> None:
    raise SystemExit(f"distrobox-matrix: {message}")


def require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} must be a mapping")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{label} must be a non-empty string")
    return value


def validate_images(images: dict[str, Any], repo_root: Path) -> list[dict[str, Any]]:
    matrix: list[dict[str, Any]] = []
    seen_refs: set[str] = set()

    for name in sorted(images):
        if not NAME_RE.fullmatch(name):
            fail(f"invalid image name {name!r}")

        image = require_mapping(images[name], f"images.{name}")

        context = require_string(image.get("context"), f"images.{name}.context")
        if not CONTEXT_RE.fullmatch(context) or "/../" in f"/{context}/":
            fail(f"images.{name}.context must be a path under distrobox/")
        context_path = (repo_root / context).resolve()
        if repo_root not in context_path.parents:
            fail(f"images.{name}.context must stay inside the repository")
        if not (context_path / "Containerfile").is_file():
            fail(f"images.{name}.context must contain a Containerfile")

        ref = require_string(image.get("ref"), f"images.{name}.ref")
        if not REF_RE.fullmatch(ref) or not ref.startswith(f"{PREFIX}{name}:"):
            fail(
                f"images.{name}.ref must be a tagged {PREFIX}{name}:... reference"
            )
        if ref in seen_refs:
            fail(f"duplicate image ref {ref!r}")
        seen_refs.add(ref)

        base = require_string(image.get("base"), f"images.{name}.base")
        if not BASE_RE.fullmatch(base):
            fail(f"images.{name}.base must be a tagged image pinned by sha256 digest")

        platforms = image.get("platforms")
        if not isinstance(platforms, list) or not platforms:
            fail(f"images.{name}.platforms must be a non-empty list")
        for index, platform in enumerate(platforms):
            if not isinstance(platform, str) or platform not in PLATFORMS:
                fail(f"images.{name}.platforms[{index}] must be linux/amd64 or linux/arm64")

        packages = image.get("packages", [])
        if not isinstance(packages, list):
            fail(f"images.{name}.packages must be a list")
        for index, package in enumerate(packages):
            if not isinstance(package, str) or not PACKAGE_RE.fullmatch(package):
                fail(f"images.{name}.packages[{index}] contains an invalid package name")

        matrix.append(
            {
                "name": name,
                "context": context,
                "ref": ref,
                "base": base,
                "platforms": ",".join(platforms),
                "packages": " ".join(packages),
            }
        )

    return matrix


def validate_containers(containers: dict[str, Any], images: dict[str, Any]) -> None:
    for name in sorted(containers):
        if not NAME_RE.fullmatch(name):
            fail(f"invalid container name {name!r}")

        container = require_mapping(containers[name], f"containers.{name}")

        image = require_string(container.get("image"), f"containers.{name}.image")
        if not IMAGE_RE.fullmatch(image):
            fail(f"containers.{name}.image contains invalid characters")
        if image not in images and not any(separator in image for separator in ("/", ":")):
            fail(f"containers.{name}.image must be an image key or a full image reference")

        for field in ("pull", "nvidia", "init", "replace"):
            if field in container and not isinstance(container[field], bool):
                fail(f"containers.{name}.{field} must be true or false")

        for field in ("exported_apps", "exported_bins"):
            values = container.get(field, [])
            if not isinstance(values, list):
                fail(f"containers.{name}.{field} must be a list")
            for index, value in enumerate(values):
                if not isinstance(value, str) or not ITEM_RE.fullmatch(value):
                    fail(f"containers.{name}.{field}[{index}] contains invalid characters")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: distrobox-matrix.py <config.json>")

    with open(sys.argv[1], encoding="utf-8") as handle:
        config = json.load(handle)

    config = require_mapping(config, "config/distrobox.yml")
    unknown = set(config) - {"images", "containers"}
    if unknown:
        fail(f"unknown top-level keys: {', '.join(sorted(unknown))}")

    images_value = config.get("images")
    containers_value = config.get("containers")
    images = require_mapping({} if images_value is None else images_value, "images")
    containers = require_mapping(
        {} if containers_value is None else containers_value, "containers"
    )

    repo_root = Path(__file__).resolve().parents[2]
    matrix = validate_images(images, repo_root)
    validate_containers(containers, images)

    print(json.dumps({"include": matrix}, separators=(",", ":")))


if __name__ == "__main__":
    main()
