# DevOps Intern Final Assessment

[![CI](https://github.com/neelstar8/devops-intern-final/actions/workflows/ci.yml/badge.svg)](https://github.com/neelstar8/devops-intern-final/actions/workflows/ci.yml)

**Author:** Neel Gadekar
**Submission date:** 2026-10-02
**Repository:** https://github.com/neelstar8/devops-intern-final

An end-to-end deployment pipeline for a containerized NGINX web application:
source control → CI → image registry → Nomad → logging and dashboards.

> **Verification status.** Every command output in this README was actually
> run on the machine described under [Prerequisites](#prerequisites). Anything
> that could not be executed is labelled **NOT VERIFIED** with the reason.
> Nothing in this document is invented. See
> [Known Limitations](#known-limitations) for the summary.

---

## Architecture

```
Source (GitHub)
      |
      v
GitHub Actions  (lint -> build -> test -> publish)
      |
      v
GHCR  ghcr.io/neelstar8/devops-intern-final
      |
      v
Nomad  (service job, Docker driver, Consul health check)
      |
      v
NGINX  (:8080, /healthz, non-root)
      |
      v
Promtail  (Docker socket discovery, relabelling)
      |
      v
Loki  (:3100, filesystem storage)
      |
      v
Grafana  (:3000, Explore / LogQL)
```

A commit on `main` is linted, built with its own SHA baked in, health-tested
as a running container, and published to GHCR under both the commit SHA and
`latest`. Nomad deploys that image, registers it in Consul, and health-checks
`/healthz`. Promtail tails the container's stdout, ships it to Loki, and
Grafana queries it.

---

## Repository layout

```
devops-intern-final/
├── README.md                     this file
├── .gitignore
├── app/
│   ├── Dockerfile                pinned base, non-root, BUILD_SHA arg
│   ├── index.html                name, date, build identifier
│   └── nginx.conf                :8080, /healthz, JSON access logs
├── scripts/
│   ├── sysinfo.sh                host + Docker summary
│   └── healthcheck.sh            asserts HTTP 200 on /healthz
├── .github/workflows/ci.yml      lint / build / test / publish
├── nomad/nginx-app.nomad.hcl     service job
├── monitoring/
│   ├── loki-config.yaml
│   └── promtail-config.yaml
├── docker-compose.yaml           Loki + Promtail + Grafana
├── loki_setup.md                 Task 6 write-up
└── docs/screenshots/
```

---

## Prerequisites

Pinned versions, as actually used:

| Tool | Version | Notes |
| --- | --- | --- |
| Docker | 29.1.3 | Docker Desktop on macOS |
| Nomad | 2.0.7 | `darwin_arm64` binary from releases.hashicorp.com |
| Consul | 2.0.4 | `darwin_arm64` binary from releases.hashicorp.com |
| ShellCheck | 0.11.0 | `brew install shellcheck` |
| Hadolint | 2.15.1 | `brew install hadolint` |
| NGINX base image | `nginx:1.27-alpine-slim` | pinned, never `latest` |
| Loki / Promtail | 3.3.2 | pinned in `docker-compose.yaml` |
| Grafana | 11.4.0 | pinned in `docker-compose.yaml` |

Host used for verification: macOS (Darwin 25.6.0), arm64, 16 GB RAM.

> On this machine Homebrew could not install Nomad or Consul — it tried to
> build from source and failed with `Your Command Line Tools are too
> outdated.` The official precompiled binaries were used instead:
>
> ```sh
> curl -fsSLO https://releases.hashicorp.com/nomad/2.0.7/nomad_2.0.7_darwin_arm64.zip
> curl -fsSLO https://releases.hashicorp.com/consul/2.0.4/consul_2.0.4_darwin_arm64.zip
> unzip -o nomad_2.0.7_darwin_arm64.zip && unzip -o consul_2.0.4_darwin_arm64.zip
> sudo mv nomad consul /usr/local/bin/
> ```

---

## Quick Start

```sh
git clone https://github.com/neelstar8/devops-intern-final.git
cd devops-intern-final
./scripts/sysinfo.sh                                                   # 1
docker build --build-arg BUILD_SHA=local -t devops-intern-final:local app/   # 2
docker run -d --name nginx-app --label service=nginx-app -p 8080:8080 devops-intern-final:local  # 3
./scripts/healthcheck.sh                                               # 4
curl -s http://localhost:8080/ | grep -A1 BUILD_SHA                    # 5
docker compose up -d                                                   # 6
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/this-path-does-not-exist  # 7
open http://localhost:3000                                             # 8
```

Eight commands. Nomad deployment is covered separately in [Task 5](#task-5--nomad).

---

## Task 1 — Git / Source Control

- Repository is **public**: https://github.com/neelstar8/devops-intern-final
- Work was done on the feature branch `feature/devops-assessment`.
- Commits are incremental and use conventional prefixes.

Observed history on the feature branch:

```
$ git log --oneline
5751835 feat: add loki monitoring stack
316bf43 fix: resolve nomad job validation warning
66f625e feat: add nomad deployment
90f9b74 ci: add github actions pipeline
97551b9 feat: add system information and healthcheck scripts
e029b0b feat: add docker configuration
fa0ee55 feat: add nginx application
8791684 chore: initialize repository with gitignore
```

Pull request, self-review, merge and tag are recorded in
[Git workflow evidence](#git-workflow-evidence) at the end of this file.

> **Repository name.** The assessment specifies `devops-intern-final`. The
> repository was originally created as `DevPipeline` and was renamed with
> `gh repo rename devops-intern-final` before any code was pushed. GitHub
> redirects the old URL.

---

## Task 2 — Shell Scripts

Both scripts are POSIX `sh`, use a shebang, fail fast, and are committed with
the executable bit set (`git update-index --chmod=+x`, verified as mode
`100755`).

> **On `set -euo pipefail`.** `pipefail` is not part of POSIX `sh`, so a bare
> `set -euo pipefail` is a bashism and would break the "POSIX shell"
> requirement. Both scripts therefore use `set -eu` unconditionally and enable
> `pipefail` only when the running shell supports it:
>
> ```sh
> set -eu
> # shellcheck disable=SC3040
> (set -o pipefail 2>/dev/null) && set -o pipefail
> ```
>
> This gives all three behaviours where available while staying POSIX-safe.
> The single `disable` directive suppresses ShellCheck's "not POSIX" notice on
> the guard line itself, which is the thing being deliberately guarded.

### Linting — observed

```
$ shellcheck -s sh scripts/sysinfo.sh scripts/healthcheck.sh
$ echo $?
0
```

No findings on either script. Hadolint and ShellCheck both also run in CI.

### `scripts/sysinfo.sh` — observed output

```
$ ./scripts/sysinfo.sh
================================
 System Information Report
================================

== Identity ==
Current user   : neel
Effective UID  : 501
Hostname       : Mac-2.local

== Kernel ==
Kernel         : Darwin 25.6.0 arm64

== Date ==
ISO date (UTC) : 2026-10-02T16:43:14Z

== Disk usage (root filesystem) ==
Filesystem        Size    Used   Avail Capacity iused ifree %iused  Mounted on
/dev/disk3s1s1   926Gi    12Gi   430Gi     3%    459k  4.3G    0%   /

== Memory ==
Total memory   : 16384 MB
Free memory    : 59 MB

== Docker daemon ==
Status         : running
Version        : 29.1.3
```

The script detects its platform: it uses `free -h` on Linux and falls back to
`sysctl`/`vm_stat` on macOS, which has no `free`.

### `scripts/healthcheck.sh` — observed output

Success path (exit code 0):

```
$ ./scripts/healthcheck.sh
Checking http://localhost:8080/healthz ...
OK: http://localhost:8080/healthz returned HTTP 200
Response body: ok
$ echo $?
0
```

Failure path against a port with nothing on it (exit code 1):

```
$ ./scripts/healthcheck.sh http://localhost:9999
Checking http://localhost:9999/healthz ...
FAIL: could not connect to http://localhost:9999/healthz
Diagnostic: the host refused the connection or timed out after 5s.
  - Is the container running?   docker ps
  - Is the port published?      docker port nginx-app
$ echo $?
1
```

The URL is taken from `$1` and defaults to `http://localhost:8080`.

---

## Task 3 — Docker / NGINX

`app/Dockerfile` highlights:

- Base `nginx:1.27-alpine-slim` — a pinned tag, never `latest`.
- Custom `nginx.conf`; NGINX listens on **8080**.
- `/healthz` returns **HTTP 200** with body `ok`.
- Runs as non-root (`USER 101:101`, the `nginx` user in the base image).
- `EXPOSE 8080` and a `HEALTHCHECK` using busybox `wget` (already present, so
  no extra packages and no size cost).
- `ARG BUILD_SHA` is stamped into `index.html` at build time and rendered on
  the page.

### Build and run — observed

```
$ docker build --build-arg BUILD_SHA=localtest -t devops-intern-final:local app/
...
#9 naming to docker.io/library/devops-intern-final:local done
#9 DONE 0.1s

$ docker run -d --name nginx-app --label service=nginx-app -p 8080:8080 devops-intern-final:local
3d4d26dce73593c5d57410e6948ed27c1083052aa5cb7e76ae8be4b43ce00c06
```

### Image size — observed

```
$ docker images devops-intern-final --format '{{.Repository}}:{{.Tag}}  {{.Size}}'
devops-intern-final:local  20.2MB
```

**20.2 MB**, against the 60 MB budget.

### Endpoints — observed

```
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8080/healthz
HTTP 200
$ curl -s http://localhost:8080/healthz
ok

$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8080/
HTTP 200
$ curl -s http://localhost:8080/ | grep -A1 'BUILD_SHA'
      <dt>Build identifier (BUILD_SHA)</dt>
      <dd>localtest</dd>
```

### Non-root and container health — observed

```
$ docker exec nginx-app id
uid=101(nginx) gid=101(nginx) groups=101(nginx)

$ docker inspect --format '{{.State.Health.Status}}' nginx-app
healthy
```

### Hadolint — observed

```
$ hadolint app/Dockerfile
$ echo $?
0
```

---

## Task 4 — GitHub Actions CI/CD

`.github/workflows/ci.yml` triggers on pushes to `main` and pull requests
targeting `main`, with four jobs:

| Job | Does |
| --- | --- |
| `lint` | `shellcheck -s sh` on both scripts; Hadolint on the Dockerfile |
| `build` | `docker build --build-arg BUILD_SHA=${{ github.sha }}`, then uploads the image as an artifact |
| `test` | loads that exact image, starts it, waits for readiness, runs `healthcheck.sh`, asserts `GET /` is 200 |
| `publish` | pushes to GHCR tagged with both the commit SHA and `latest` |

Security choices:

- Workflow-level `permissions: contents: read`; only `publish` adds
  `packages: write`.
- `publish` is gated on `github.event_name == 'push' && github.ref == 'refs/heads/main'`,
  so pull requests never publish.
- Auth uses the run-scoped `secrets.GITHUB_TOKEN`. No long-lived credentials
  and no stored registry secrets.
- Actions are pinned to a major version (`actions/checkout@v4`,
  `actions/upload-artifact@v4`, `actions/download-artifact@v4`). Hadolint runs
  from the pinned image `hadolint/hadolint:v2.12.0` rather than a third-party
  action, which keeps the number of external actions down.

`build` and `test` are separate jobs, so `test` exercises the very same image
artifact that `build` produced instead of rebuilding it.

### CI on the pull request — observed

```
$ gh run view 37036330285
✓ feature/devops-assessment CI neelstar8/devops-intern-final#1 · 37036330285
Triggered via pull_request

JOBS
✓ Lint (ShellCheck + Hadolint) in 13s (ID 110935343296)
✓ Build image in 18s (ID 110935442818)
✓ Test container health in 8s (ID 110935575519)
- Publish to GHCR in 0s (ID 110935642326)
```

`lint`, `build` and `test` passed; `publish` was correctly skipped because the
trigger was a pull request. The run emitted two advisory annotations (Node 20
deprecation for `actions/*`, and the upcoming `ubuntu-latest` migration to
Ubuntu 26) — neither is an error.

### CI on `main` and GHCR publication

See [Git workflow evidence](#git-workflow-evidence).

---

## Task 5 — Nomad

`nomad/nginx-app.nomad.hcl`:

- `type = "service"`, one group (`web`), one task (`nginx`).
- Docker driver, image pulled from GHCR.
- Image tag parameterized through an HCL variable:
  `image = "ghcr.io/neelstar8/devops-intern-final:${var.image_tag}"`.
- `cpu = 100` MHz, `memory = 64` MB, exactly as specified.
- Dynamic named port `http` mapped to container port 8080 via `to = 8080`.
- Consul HTTP check on `/healthz`, `interval = "10s"`, `timeout = "2s"`.
- `update` stanza: `max_parallel = 1`, `min_healthy_time = "10s"`,
  `healthy_deadline = "2m"`, `auto_revert = true`.
- `restart` and `reschedule` policies included.

### Starting local agents

```sh
consul agent -dev -client=127.0.0.1
nomad agent -dev -bind=127.0.0.1 -config=nomad-dev.hcl
```

`nomad-dev.hcl` is a local-only file (not committed) needed on Apple Silicon —
see [Troubleshooting](#troubleshooting) item 3:

```hcl
client {
  cpu_total_compute = 4000
}
```

### `nomad job validate` — observed

```
$ nomad job validate -var="image_tag=latest" nomad/nginx-app.nomad.hcl
Job validation successful
```

Clean, no warnings. (It initially warned about a missing `shutdown_delay`;
see Troubleshooting item 4.)

### `nomad job plan` — observed

```
$ nomad job plan -var="image_tag=latest" nomad/nginx-app.nomad.hcl
+ Job: "nginx-app"
+ Task Group: "web" (1 create)
  + Task: "nginx" (forces create)

Scheduler dry-run:
- All tasks successfully allocated.

Job Modify Index: 0
```

Agent and node state at that point:

```
$ nomad node status
ID        Node Pool  DC   Name         Class   Drain  Eligibility  Status
ddcce0b1  default    dc1  Mac-2.local  <none>  false  eligible     ready

$ nomad node status -self | grep -A3 "Allocated Resources"
Allocated Resources
CPU         Memory      Disk         Alloc Count
0/4000 MHz  0 B/16 GiB  0 B/926 GiB  0
```

Driver status on the node: `docker,java,raw_exec`.

### `nomad job run` and healthy allocation status

**NOT VERIFIED — the local Docker daemon cannot start containers on this
machine.** Nomad and Consul are installed and running, `validate` and `plan`
both succeed, and the scheduler confirms the allocation can be placed. But
`nomad job run` would hand the container to Docker, and Docker container
startup is currently broken here for the memory reason documented in
Troubleshooting item 5. Submitting the job would produce a failed allocation
for reasons unrelated to the job specification, so it was not run and no
allocation output is shown.

To finish this step once Docker is healthy:

```sh
consul agent -dev -client=127.0.0.1 &
nomad agent -dev -bind=127.0.0.1 -config=nomad-dev.hcl &
nomad job run -var="image_tag=latest" nomad/nginx-app.nomad.hcl
nomad job status nginx-app          # expect Status = running, 1 running alloc
nomad alloc status <alloc-id>       # expect Tasks "nginx" state = running
consul members                      # expect the node alive
curl -s http://localhost:8500/v1/health/checks/nginx-app | jq '.[].Status'
                                    # expect "passing"
```

---

## Task 6 — Logging / Observability

Full write-up: **[loki_setup.md](loki_setup.md)**.

- `docker-compose.yaml` runs Loki 3.3.2, Promtail 3.3.2 and Grafana 11.4.0,
  all pinned.
- `monitoring/loki-config.yaml` — single-process Loki, filesystem storage,
  auth disabled, TSDB schema v13.
- `monitoring/promtail-config.yaml` — `docker_sd_configs` over the Docker
  socket, relabelled to `job`, `container`, `service` and `nomad_alloc_id`.
- NGINX emits JSON access logs, so non-200 responses can be isolated with
  `| json | status != 200` instead of a fragile regex.

Intended query, after requesting `/this-path-does-not-exist`:

```logql
{container="nginx-app"} | json | status != 200
```

### Status: PARTIALLY VERIFIED

| Item | Status |
| --- | --- |
| Configs written and YAML-valid | **PASS** |
| Loki / Promtail / Grafana images pull | **PASS** |
| Containers running | **NOT VERIFIED** — Docker cannot start containers (Troubleshooting 5) |
| Loki ingestion proven | **NOT VERIFIED** |
| LogQL non-200 query result | **NOT VERIFIED** |
| Grafana Explore screenshot | **NOT CAPTURED** — `docs/screenshots/` is empty |

No Loki output or Grafana screenshot is shown here because none was produced.
The remaining steps are listed in `loki_setup.md`.

---

## Troubleshooting

Five failures actually hit while building this, in order.

### 1. Base image blew the 60 MB budget before any content was added

`nginx:1.27-alpine` is far larger on arm64 than its amd64 reputation suggests:

```
$ docker images nginx --format '{{.Repository}}:{{.Tag}} {{.Size}}'
nginx:1.27-alpine 76.8MB
```

76.8 MB against a 60 MB limit, with nothing of ours in it yet.

**Fix:** switched to the official `-slim` variant, which drops modules a
static site never uses. Final image **20.2 MB**. Pinning discipline is
unchanged — still an explicit tag, never `latest`.

### 2. Hadolint rejected the first Dockerfile

```
app/Dockerfile:17 DL3066 info: Non-numeric user-id may not be resolvable by host system
app/Dockerfile:22 DL3025 warning: Use arguments JSON notation for CMD and ENTRYPOINT arguments
```

**Fix:** both were corrected rather than suppressed.

- `DL3066`: replaced `USER nginx` with `USER 101:101`, after confirming the
  id with `docker run --rm nginx:1.27-alpine sh -c 'id nginx'` →
  `uid=101(nginx) gid=101(nginx)`.
- `DL3025`: the `HEALTHCHECK` used shell form only because of a trailing
  `|| exit 1`. `wget --spider` already exits non-zero on failure, so the
  `|| exit 1` was redundant and the command became valid JSON form.

Hadolint now reports nothing.

### 3. Nomad refused to place the allocation: "cpu exhausted"

```
$ nomad job plan -var="image_tag=latest" nomad/nginx-app.nomad.hcl
Scheduler dry-run:
- WARNING: Failed to place all allocations.
  Task Group "web" (failed to place 1 allocation):
    * Resources exhausted on 1 nodes
    * Dimension "cpu" exhausted on 1 nodes
```

The node had fingerprinted almost no CPU:

```
$ nomad node status -self | grep -A3 "Allocated Resources"
Allocated Resources
CPU       Memory      Disk         Alloc Count
0/28 MHz  0 B/16 GiB  0 B/926 GiB  0
```

**28 MHz total.** Nomad cannot read the clock frequency on Apple Silicon, so
the job's required `cpu = 100` could never fit.

**Fix:** corrected the *agent's* fingerprint rather than weakening the job,
since `cpu = 100` is a specified requirement. A local agent config:

```hcl
client {
  cpu_total_compute = 4000
}
```

started with `nomad agent -dev -config=nomad-dev.hcl`. The node then reported
`0/4000 MHz` and the plan returned `All tasks successfully allocated.` This
file is intentionally not committed — it is a workaround for one developer
machine, not part of the deliverable.

### 4. `nomad job validate` warned about `shutdown_delay`

```
$ nomad job validate -var="image_tag=latest" nomad/nginx-app.nomad.hcl
Job Warnings:
1 warning:

* group "web" defines services, but neither the group nor any of its tasks have shutdown_delay set
```

**Fix:** added `shutdown_delay = "5s"` to the group, so in-flight requests
drain while Consul deregisters the service. Validation is now clean. Committed
as `fix: resolve nomad job validation warning`.

### 5. Docker daemon stopped being able to start containers

`docker compose up -d` hung, then:

```
Container loki Starting
error during connect: Post "http://.../containers/<id>/start": EOF
```

All three containers were left in `Created`. Even the app container, which had
been running happily for ten minutes, could no longer be restarted.

Root cause:

```
$ docker info --format '{{.MemTotal}}'
8217448448                  # Docker Desktop VM allocated 8.2 GB

$ top -l 1 -s 0 | grep PhysMem
PhysMem: 15G used (2097M wired, 4743M compressor), 141M unused.
```

A 16 GB host with ~141 MB unused and 4.7 GB compressed is swapping hard. The
Docker VM could not get the 8.2 GB it was promised, so `containers/<id>/start`
died mid-request. Quitting and relaunching Docker Desktop did **not** fix it,
which ruled out a transient daemon fault. Image *pulls* kept working, ruling
out config and registry problems.

**Fix: identified, not yet applied.** Free host memory, then lower Docker
Desktop's memory limit (Settings → Resources) to around 4 GB — plenty for this
stack — and retry. This is what blocks the remaining Task 5 and Task 6
verification; it is an environment issue, not a defect in the committed
configuration.

---

## Known Limitations

1. **Loki ingestion is not proven.** Configs are complete and YAML-valid, and
   the images pull, but no container ever started, so no LogQL result exists.
2. **No Grafana screenshot.** `docs/screenshots/` is empty. Fabricating one
   was not an option.
3. **`nomad job run` was never executed.** `validate` and `plan` pass against
   a live agent with the Docker driver detected, but running the job depends
   on the same broken Docker startup.
4. **Nomad on Apple Silicon needs an uncommitted agent override**
   (`cpu_total_compute`). Not needed on Linux.
5. **`pipefail` is conditional**, because it is not POSIX. See Task 2.
6. **Grafana runs with anonymous admin access** so a reviewer can open Explore
   without credentials. Local convenience only; not a production setting.
7. **The Nomad job hardcodes the GHCR registry path.** Only the tag is
   parameterized, which is what the assessment asked for.
8. **Verified on macOS/arm64 only.** CI covers `ubuntu-latest`.

---

## Git workflow evidence

All of the following was actually executed; outputs are copied verbatim.

### Branch and commits

Nine commits on `feature/devops-assessment`, conventional prefixes
(`chore:`, `feat:`, `ci:`, `fix:`, `docs:`), no single giant commit:

```
$ git log --oneline
726cb59 Merge pull request #1 from neelstar8/feature/devops-assessment
3fbca55 docs: keep screenshots directory in version control
9373994 docs: add assessment documentation
5751835 feat: add loki monitoring stack
316bf43 fix: resolve nomad job validation warning
66f625e feat: add nomad deployment
90f9b74 ci: add github actions pipeline
97551b9 feat: add system information and healthcheck scripts
e029b0b feat: add docker configuration
fa0ee55 feat: add nginx application
8791684 chore: initialize repository with gitignore
```

### Pull request, self-review and merge

- PR: https://github.com/neelstar8/devops-intern-final/pull/1
- Self-review posted as a review on that PR (`neelstar8: COMMENTED`), covering
  each file plus the two gaps being knowingly merged.

```
$ gh pr view 1 --json state,mergedAt,mergeCommit
state=MERGED  mergedAt=2026-10-02T17:03:01Z
mergeCommit=726cb59a795eb1504cdef96e5ab9ed1fd2d0a979
```

Three CI runs on the PR, all green, with `publish` skipped every time:

```
$ gh run list --branch feature/devops-assessment --limit 3
completed  success  CI  feature/devops-assessment  pull_request  37037928167  39s
completed  success  CI  feature/devops-assessment  pull_request  37037893837  46s
completed  success  CI  feature/devops-assessment  pull_request  37036330285  49s
```

### CI on `main` — observed

```
$ gh run view 37038074339
✓ main CI · 37038074339
Triggered via push

JOBS
✓ Lint (ShellCheck + Hadolint) in 8s (ID 110941103936)
✓ Build image in 19s (ID 110941169458)
✓ Test container health in 12s (ID 110941306785)
✓ Publish to GHCR in 17s (ID 110941401631)
```

All four jobs green. `publish` ran this time because the trigger was a push
to `main`.

### GHCR publication — observed

From the `publish` job log:

```
Login Succeeded
726cb59a795eb1504cdef96e5ab9ed1fd2d0a979: digest: sha256:2e2e4aeda5e34622b6627d0dc654c1d4acab509f554d71e944102ac04bbfa612 size: 2398
latest: digest: sha256:2e2e4aeda5e34622b6627d0dc654c1d4acab509f554d71e944102ac04bbfa612 size: 2398
```

Confirmed independently against the registry, unauthenticated:

```
$ curl -s -H "Authorization: Bearer $TOK" \
    https://ghcr.io/v2/neelstar8/devops-intern-final/tags/list
{"name":"neelstar8/devops-intern-final","tags":["726cb59a795eb1504cdef96e5ab9ed1fd2d0a979","latest"]}
```

Both tags exist and point at the same digest. The image is:

```
ghcr.io/neelstar8/devops-intern-final:latest
ghcr.io/neelstar8/devops-intern-final:726cb59a795eb1504cdef96e5ab9ed1fd2d0a979
```

`BUILD_SHA` was passed as `726cb59a795eb1504cdef96e5ab9ed1fd2d0a979`, so the
published page renders that commit SHA as its build identifier.

### `main` contains the completed project — observed

```
$ git checkout main && git pull && ls -A
.github  .gitignore  README.md  app  docker-compose.yaml
docs  loki_setup.md  monitoring  nomad  scripts

$ git rev-parse main
726cb59a795eb1504cdef96e5ab9ed1fd2d0a979
```

### Release tag

The annotated tag `v1.0.0` is created on `main` after this documentation is
merged, so it points at the final submission state:

```sh
git checkout main && git pull
git tag -a v1.0.0 -m "DevOps Intern Final Assessment submission"
git push origin v1.0.0
```

Verify with `git show v1.0.0 --stat` or
https://github.com/neelstar8/devops-intern-final/releases/tag/v1.0.0
