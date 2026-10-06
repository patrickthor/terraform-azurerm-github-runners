# ==============================================================================
# Runner image — module-owned
#
# The scaler creates ephemeral ACI runners from this image. The module owns the
# Dockerfile and the installed tool versions; consumers own only the private ACR
# they build it into. ACI continues to pull exclusively from that private ACR.
#
# Azure CLI is the reason this image exists. The previously imported upstream
# image ships no `az`, so any workflow step using azure/login or `az storage`
# failed on these runners.
# ==============================================================================

# The upstream tag is intentionally resolved to the linux/amd64 manifest digest.
# Updating the runner is a reviewed change rather than an implicit pull of latest.
# Verified: this digest is a single-platform OCI image manifest with
# architecture=amd64, os=linux — not a multi-arch index.
FROM ghcr.io/myoung34/docker-github-actions-runner@sha256:173ca65612b178a575971302bb31658e0cb4ec2cf48a0a817819e20fe7ef98f9

# Build-time only. The upstream config sets no OCI `User`, so root is already the
# inherited runtime default and this line changes no runtime behavior — it only
# makes the privilege level explicit for the package installation below.
# The upstream entrypoint resolves `RUN_AS_ROOT=${RUN_AS_ROOT:="true"}`; set that
# variable to "false" in the ACI environment to have it drop to the `runner`
# account via gosu. See README.md.
USER root

# The pinned upstream runner currently uses Ubuntu 20.04 (focal). 2.72.0 is the
# newest Azure CLI package Microsoft publishes in the focal repository. Packages
# are verified through Microsoft's signing key instead of piping an install
# script into a privileged shell at job runtime.
ARG AZURE_CLI_VERSION="2.72.0-1~focal"
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && chmod go+r /etc/apt/keyrings/microsoft.gpg \
    && printf '%s\n' \
      'Types: deb' \
      'URIs: https://packages.microsoft.com/repos/azure-cli/' \
      'Suites: focal' \
      'Components: main' \
      'Architectures: amd64' \
      'Signed-by: /etc/apt/keyrings/microsoft.gpg' \
      > /etc/apt/sources.list.d/azure-cli.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends "azure-cli=${AZURE_CLI_VERSION}" \
    && az version \
    && rm -rf /var/lib/apt/lists/*

# ENTRYPOINT and CMD are deliberately not overridden. They are inherited from the
# upstream image as ["/entrypoint.sh"] and
# ["./bin/Runner.Listener","run","--startuptype","service"], which preserves the
# ephemeral registration flow and the environment-variable contract the scaler
# depends on (REPO_URL, RUNNER_NAME, LABELS, EPHEMERAL, RUNNER_TOKEN).
