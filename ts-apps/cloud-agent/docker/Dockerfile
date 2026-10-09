# syntax=docker/dockerfile:1
#
# legalese-cloud-agent: the headless Legalese AI harness for one cloud
# session (cloud-sessions spec §5.1, §5.3, §14). Built for linux/arm64 by
# .github/workflows/cloud-agent-image.yml.
#
# Build context: ts-apps/cloud-agent, with
#   dist/cloud-agent.cjs   the esbuild bundle (npm run build)
#   bin/jl4-lsp            the linux-arm64 language server (cabal build, stripped)
#
#   docker buildx build --platform linux/arm64 -f docker/Dockerfile .
#
# node:24-trixie-slim has glibc 2.41; jl4-lsp is built on Ubuntu 24.04 and
# needs >= 2.39, so Alpine doesn't work. No l4 CLI, no Graphviz: the harness
# only uses the language server, which embeds the core libraries.
FROM node:24-trixie-slim

# The runtime user is 1000:1000 (the node image's "node" user); its HOME is
# a tmpfs at /home/agent in the task definition, /workspace the S3 Files
# mount. Package versions follow the base image's Debian release (pinning
# exact versions breaks every time trixie ships a security update).
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git tini ca-certificates libgmp10 libffi8 zlib1g \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/agent /workspace \
 && chown 1000:1000 /home/agent /workspace

COPY --chmod=0755 bin/jl4-lsp /app/bin/jl4-lsp
COPY --chmod=0644 dist/cloud-agent.cjs /app/cloud-agent.cjs
COPY --chmod=0755 docker/entrypoint.sh /app/entrypoint

USER 1000:1000
WORKDIR /home/agent
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint"]
