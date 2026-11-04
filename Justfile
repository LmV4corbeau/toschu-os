set dotenv-filename := "image-template.env"
set dotenv-load

image_name := env_var("IMAGE_NAME")
image_registry := env_var("IMAGE_REGISTRY")
image_owner := env_var("IMAGE_OWNER")
default_tag := env_var("DEFAULT_TAG")

alias push := push-image

default:
    @just --list

# Build the image locally with Podman.
build:
    podman build --pull=newer \
        --tag "{{ image_name }}:{{ default_tag }}" \
        --file Containerfile .

# Build as root so `bootc switch --transport containers-storage` can use it.
build-root:
    sudo podman build --pull=newer \
        --tag "{{ image_name }}:{{ default_tag }}" \
        --file Containerfile .

# Push the locally built image to GitHub Container Registry.
# Run `podman login ghcr.io` first.
push-image:
    podman push "{{ image_name }}:{{ default_tag }}" \
        "{{ image_registry }}/{{ image_owner }}/{{ image_name }}:{{ default_tag }}"
    podman push "{{ image_name }}:{{ default_tag }}" \
        "{{ image_registry }}/{{ image_owner }}/{{ image_name }}:latest"

# Run ShellCheck on all shell scripts.
lint:
    find . -iname "*.sh" -type f -exec shellcheck "{}" ";"
    shellcheck system_files/usr/bin/toschu-distrobox-setup

# Format all shell scripts.
format:
    find . -iname "*.sh" -type f -exec shfmt --write "{}" ";"
    shfmt --write system_files/usr/bin/toschu-distrobox-setup
