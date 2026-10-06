# Runner image

The container image the scaler runs as an ephemeral GitHub Actions runner on Azure Container Instances.

This module owns the Dockerfile and every tool version in it. Consumers own only the private ACR they build it into, and ACI pulls exclusively from that private registry — never from public GHCR.

## Why Azure CLI is here

The platform previously imported `ghcr.io/myoung34/docker-github-actions-runner` directly. That image ships no `az`, so any workflow step using `azure/login` or `az storage` failed on these runners. This image adds Azure CLI from Microsoft's signed package repository on top of that same upstream runner.

Installation uses the apt repository with Microsoft's signing key in `/etc/apt/keyrings`, not `curl | bash`. Packages are signature-verified at install time, and `az version` runs during the build so a broken install fails the build rather than the first job.

## What is preserved

The image does not override `ENTRYPOINT` or `CMD`. Both are inherited from upstream:

```
ENTRYPOINT ["/entrypoint.sh"]
CMD ["./bin/Runner.Listener", "run", "--startuptype", "service"]
```

That keeps the ephemeral registration and deregistration flow intact, along with the environment-variable contract the scaler relies on. The scaler sends:

| Variable | Source |
|---|---|
| `REPO_URL` | `https://github.com/{github_repo}` |
| `RUNNER_NAME` | `{runner_name_prefix}-{job hash}` |
| `LABELS` | `runner_labels` |
| `EPHEMERAL` | always `true` |
| `RUNNER_TOKEN` | registration token, passed as an ACI secure value |
| `ARM_CLIENT_ID` | client ID of the runner pull identity, for IMDS auth |

Adding a package changes none of that.

## Build

Consumers build straight into their own registry, which avoids pulling the image across a workstation:

```bash
ACR_NAME=$(terraform output -raw acr_login_server | cut -d. -f1)

az acr build \
  --registry "$ACR_NAME" \
  --image actions-runner:latest \
  --file Dockerfile \
  ./runner-image
```

ACR Tasks builds on `linux/amd64`, which is what ACI runs. Locally the platform must be explicit, because a build on an arm64 workstation would otherwise produce an image ACI cannot execute:

```bash
docker build --platform linux/amd64 -t github-runner:test runner-image
```

## Verify

```bash
# Azure CLI is present and runnable. --entrypoint bypasses the runner
# registration flow, so this does not try to join a repository.
docker run --rm --platform linux/amd64 --entrypoint az github-runner:test version

# Other tools the workflows expect
docker run --rm --platform linux/amd64 --entrypoint git github-runner:test --version
docker run --rm --platform linux/amd64 --entrypoint jq  github-runner:test --version
```

Never smoke-test by running the image without `--entrypoint`. The default entrypoint attempts to register a runner, and with a live `RUNNER_TOKEN` it would join your real repository.

CI runs this build, the `az version` check, the tool probes, a runtime-user report, and a credential scan of the image layers on every push and pull request — see [`.github/workflows/validate.yml`](../.github/workflows/validate.yml).

## Known gaps

Three things are deliberately not solved here, because the base image choice constrains them. They are tracked in [IMPROVEMENTS.md](../IMPROVEMENTS.md).

**The OS and CLI are both out of support.** Pinning to this upstream image inherits Ubuntu 20.04, whose standard security support ended in May 2025. `2.72.0-1~focal` is genuinely the newest Azure CLI in Microsoft's focal feed — the noble feed is already at `2.91.0`, nineteen minor versions ahead. Digest pinning freezes that exposure rather than fixing it. Moving to Ubuntu 24.04 means rebasing off this upstream image and reimplementing the entrypoint, which is a behavioral change rather than a package addition.

**Jobs run as root.** Upstream sets no OCI `User` and its entrypoint defaults `RUN_AS_ROOT` to `true`, so workflow steps execute as root. Setting `RUN_AS_ROOT=false` in the ACI environment makes the entrypoint drop to the `runner` account with gosu. That is a scaler change, so it is out of scope for this image and untested here.

**There is no scan, SBOM, or signature gate.** A digest proves byte identity, not that the bytes are safe or that they came from a reviewed build.

## Updating the base image

The `FROM` digest is a reviewed change. To move it:

```bash
docker buildx imagetools inspect \
  ghcr.io/myoung34/docker-github-actions-runner:latest --format '{{json .Manifest}}'
```

Take the `linux/amd64` manifest digest, not the index digest, and confirm the new base still reports `architecture: amd64`. If the upstream base OS changes, re-check that `Suites:` in the Azure CLI source still matches the new release codename — a stale codename there installs nothing and fails the build at `az version`.
