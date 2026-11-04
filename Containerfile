# Base image. Override with --build-arg BASE_IMAGE=... if needed.
# Must be declared before the first FROM so Docker can use it in FROM.
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable@sha256:9ef3035588c6760e96c5064a1920db35c012c6c8e7d20ac6c1c31a04ed682e0b

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="toschu-os"
LABEL org.opencontainers.image.description="Custom Bazzite image"
LABEL org.opencontainers.image.source="https://github.com/LmV4corbeau/toschu-os"

# Make /opt immutable if packages need to write there. Bazzite/Fedora symlinks
# /opt to /var/opt, and bootc may discard those files on updates.
# RUN rm /opt && mkdir /opt

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build.sh

RUN bootc container lint
