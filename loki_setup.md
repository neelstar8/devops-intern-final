# Loki / Promtail / Grafana Setup (Task 6)

Status: **PARTIALLY VERIFIED.** The configuration is complete and the three
images pull successfully, but the containers could not be started on this
machine. See [Blocker](#blocker-container-startup) below. Everything marked
*observed* was actually run; everything marked *expected* has not been
confirmed yet and must be re-checked once the blocker is cleared.

## 1. Startup

```sh
# From the repository root.
docker compose up -d

# The app itself is not part of the compose file. Promtail finds it over the
# Docker socket, so the `service` label must be set when starting it.
docker run -d --name nginx-app --label service=nginx-app \
  -p 8080:8080 devops-intern-final:local
```

Endpoints:

| Service | URL |
| --- | --- |
| Loki | http://localhost:3100 |
| Grafana | http://localhost:3000 |
| App | http://localhost:8080 |

Grafana runs with anonymous admin access enabled (local only), so no login is
needed. Add Loki as a datasource once:

1. Grafana → **Connections → Data sources → Add new data source → Loki**
2. URL: `http://loki:3100` (the compose service name, not `localhost`)
3. **Save & test**

## 2. Labels

Promtail uses `docker_sd_configs` to discover every running container and
relabels the Docker metadata into these Loki labels:

| Label | Source | Example |
| --- | --- | --- |
| `job` | static, set by the scrape config | `docker` |
| `container` | `__meta_docker_container_name`, leading `/` stripped | `nginx-app` |
| `service` | `__meta_docker_container_label_service` | `nginx-app` |
| `nomad_alloc_id` | `__meta_docker_container_label_com_hashicorp_nomad_alloc_id` | set only when Nomad started the container |

`nomad_alloc_id` is deliberately best-effort: it is populated when the
container is launched by the Nomad job and absent when launched by
`docker run`. Both cases are covered by the same scrape config.

NGINX writes access logs to stdout as JSON (see `app/nginx.conf`), which is
what makes the `status` field available to LogQL without a regex parser.

## 3. Queries

Generate a deliberate miss first, so there is a non-200 line to find:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/this-path-does-not-exist
# expected: 404
```

Then in **Grafana → Explore → Loki**, run:

```logql
# All logs from the app container.
{container="nginx-app"}

# Access logs with a non-200 response status.
{container="nginx-app"} | json | status != 200

# The deliberate missing path specifically.
{container="nginx-app"} | json | status = 404 | path = "/this-path-does-not-exist"
```

The same query from the command line:

```sh
curl -sG http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={container="nginx-app"} | json | status != 200' \
  --data-urlencode 'limit=10' | jq '.data.result'
```

## 4. Results

**NOT VERIFIED.** No query has been run against a live Loki instance yet,
because the containers never reached the running state on this machine. No
sample result is shown here rather than an invented one.

Required Grafana Explore screenshot: **not yet captured.** It must be saved to
`docs/screenshots/grafana-explore-non200.png` once the stack runs.

## 5. Problems encountered

### Blocker: container startup

Every container start against the local Docker daemon hangs and the request
is dropped:

```
Container loki Starting
error during connect: Post "http://.../containers/<id>/start": EOF
```

Diagnosis (observed):

```
$ docker info --format '{{.MemTotal}}'
8217448448            # Docker Desktop VM is allocated 8.2 GB

$ top -l 1 -s 0 | grep PhysMem
PhysMem: 15G used (2097M wired, 4743M compressor), 141M unused.
```

The host has 16 GB of RAM with ~141 MB unused and ~4.7 GB in the compressor,
i.e. it is swapping heavily. The Docker VM cannot obtain the memory it was
promised, so `containers/<id>/start` dies mid-request. Containers are left in
the `Created` state. Restarting Docker Desktop did not help, which confirms
the cause is host memory rather than a transient daemon fault.

Supporting evidence that this is environmental and not a config error:

- The same images **pull** successfully, so the tags and registry access are fine.
- A pre-existing container on this machine (`vibrant_moser`) has also been
  stuck in `Created` for months.
- The app container ran fine earlier in the session and only became
  unstartable after the host filled up.

### Fix required (not yet applied)

Reduce memory pressure, then retry:

1. Quit memory-heavy applications (Chrome, Antigravity, and similar).
2. Docker Desktop → **Settings → Resources** → lower **Memory limit** to
   about **4 GB**, which is ample for Loki + Promtail + Grafana, then
   **Apply & restart**.
3. Re-run the startup commands in section 1 and the queries in section 3.
4. Capture the Grafana Explore screenshot to
   `docs/screenshots/grafana-explore-non200.png`.

### Fixes already applied

- **Promtail could not have labelled the app by service name.** `docker run`
  sets no Compose labels, so a `com.docker.compose.service` relabel would have
  produced an empty `service` label. Resolved by relabelling from a plain
  `service` Docker label and documenting `--label service=nginx-app` as part
  of the run command.
- **Status filtering would have needed fragile regex.** The default NGINX
  combined log format is not machine-readable. Resolved by emitting JSON
  access logs, so LogQL can use `| json | status != 200` directly.
