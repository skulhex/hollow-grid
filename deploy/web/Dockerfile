FROM debian:bookworm-slim AS godot-export

ARG GODOT_VERSION=4.6.2
ARG GODOT_STATUS=stable
ARG TARGETARCH

ENV GODOT_RELEASE="${GODOT_VERSION}-${GODOT_STATUS}"
ENV GODOT_TEMPLATES_DIR="/root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_STATUS}"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        libasound2 \
        libfontconfig1 \
        libgl1 \
        libglib2.0-0 \
        libx11-6 \
        libxcursor1 \
        libxext6 \
        libxi6 \
        libxinerama1 \
        libxrandr2 \
        libxrender1 \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) GODOT_ARCH="x86_64" ;; \
        arm64) GODOT_ARCH="arm64" ;; \
        *) echo "Unsupported Docker TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fSL \
        "https://github.com/godotengine/godot-builds/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.${GODOT_ARCH}.zip" \
        -o /tmp/godot.zip; \
    unzip /tmp/godot.zip -d /usr/local/bin; \
    find /usr/local/bin -maxdepth 1 -type f -name "Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.*" -exec mv {} /usr/local/bin/godot \; ; \
    chmod +x /usr/local/bin/godot; \
    rm /tmp/godot.zip

RUN set -eux; \
    mkdir -p "${GODOT_TEMPLATES_DIR}"; \
    curl -fSL \
        "https://github.com/godotengine/godot-builds/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_export_templates.tpz" \
        -o /tmp/templates.tpz; \
    unzip /tmp/templates.tpz "templates/web*.zip" "templates/version.txt" -d /tmp/templates; \
    cp /tmp/templates/templates/* "${GODOT_TEMPLATES_DIR}/"; \
    rm -rf /tmp/templates /tmp/templates.tpz

WORKDIR /src

COPY game ./game

RUN mkdir -p /export \
    && godot --headless --path /src/game --export-release "Web" /export/index.html

FROM nginx:alpine AS runtime

COPY deploy/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=godot-export /export /usr/share/nginx/html
