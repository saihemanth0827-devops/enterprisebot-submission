# Enterprise Bot — HTTP Service

A lightweight, dependency-free HTTP service built with Python 3.12 and packaged in a Docker container. The service exposes a health endpoint and a JSON endpoint that returns application metadata.

## Features

- Lightweight HTTP server using Python's standard library.
- Health-check endpoint at `/healthz`.
- JSON application information at `/`.
- Dynamic configuration using Kubernetes projected ConfigMap files, with environment-variable fallback.
- Multi-stage Docker build with a Python compilation check.
- Non-root container execution.
- Read-only filesystem compatibility.
- Docker health check for container health monitoring.

## Technology Stack

- **Language:** Python 3.12
- **HTTP server:** `http.server`
- **Containerization:** Docker
- **Orchestration:** Kubernetes
- **Packaging:** Helm

## Project Structure

```text
.
├── app.py
├── Dockerfile
└── README.md
```

The Helm chart and Kubernetes configuration can be maintained in their respective directories in the full repository.

## HTTP Endpoints

### `GET /`

Returns application metadata as JSON.

Example response:

```json
{
  "app": "demo",
  "version": "1.0.0",
  "pod": "container-hostname"
}
```

The `app` and `version` values are configurable. The `pod` field contains the hostname returned by the running environment, which is typically the pod name in Kubernetes.

### `GET /healthz`

Returns HTTP `200 OK` when the HTTP server is responding.

Example response:

```text
ok
```

This endpoint is suitable for basic container health checks and Kubernetes health probes.

### Unsupported endpoints

Requests to unsupported paths return HTTP `404 Not Found`.

## Configuration

The service supports environment variables and configuration files.

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8080` | HTTP listening port |
| `CONFIG_DIR` | `/etc/demo-config` | Directory containing projected configuration files |
| `APP_NAME` | `demo` | Application name |
| `VERSION` | `1.0.0` | Application version |

### Configuration precedence

For `APP_NAME` and `VERSION`, the service follows this order:

1. Read the corresponding file from `CONFIG_DIR`.
2. If the file is missing, unreadable, or empty, fall back to the environment variable.
3. If the environment variable is also unavailable, use the default value.

The configuration files are read when handling each request to `/`, allowing the application to observe updated projected ConfigMap files after Kubernetes refreshes the mounted volume.

**Note:** Kubernetes does not update environment variables inside an already-running container when a ConfigMap changes. Projected-volume updates are also asynchronous, so a configuration change may take time to become visible.

Example configuration files:

`/etc/demo-config/APP_NAME`

```text
enterprise-bot
```

`/etc/demo-config/VERSION`

```text
1.0.0
```

## Run Locally

Requirements: Python 3.12 or a compatible Python version.

Start the application:

```bash
python app.py
```

The server listens on `0.0.0.0:8080` by default.

Test the endpoints:

```bash
curl -i http://127.0.0.1:8080/
curl -i http://127.0.0.1:8080/healthz
```

Override the configuration through environment variables:

```bash
APP_NAME=enterprise-bot VERSION=1.0.0 PORT=8080 python app.py
```

## Docker

### Build the image

Run this command from the directory containing `Dockerfile` and `app.py`:

```bash
docker build -t enterprise-bot:1.0.0 .
```

### Run the container

```bash
docker run -d \
  --name enterprise-bot \
  -p 8080:8080 \
  -e APP_NAME=enterprise-bot \
  -e VERSION=1.0.0 \
  enterprise-bot:1.0.0
```

### Test the container

```bash
curl -i http://127.0.0.1:8080/
curl -i http://127.0.0.1:8080/healthz
docker inspect --format='{{.State.Health.Status}}' enterprise-bot
docker logs enterprise-bot
```

Remove the test container when finished:

```bash
docker rm -f enterprise-bot
```

### Test file-based configuration

Create configuration files:

```bash
mkdir -p demo-config
printf 'enterprise-bot\n' > demo-config/APP_NAME
printf '1.0.0\n' > demo-config/VERSION
```

Run the container with the configuration directory mounted read-only:

```bash
docker run -d \
  --name enterprise-bot-config \
  -p 8080:8080 \
  -v "$(pwd)/demo-config:/etc/demo-config:ro" \
  enterprise-bot:1.0.0
```

Verify the response:

```bash
curl -sS http://127.0.0.1:8080/
```

The returned application name and version should match the mounted files.

## Dockerfile Design

The Dockerfile uses two stages:

**Builder stage**
- Uses the pinned Python base-image tag `python:3.12.7-slim-bookworm`.
- Copies `app.py` into the build directory.
- Runs `python -m py_compile app.py` to detect Python syntax errors.

**Runtime stage**
- Uses the same Python base-image tag.
- Copies only the application source from the builder stage.
- Creates a dedicated non-root user with UID `10001`.
- Configures the application port and configuration directory.
- Defines a Docker `HEALTHCHECK` that calls `/healthz`.
- Starts the application using Python.

The runtime image does not need application-specific third-party Python packages because the service uses the standard library.

## Kubernetes and Helm Integration

For Kubernetes deployment, the application can be exposed through a Service and configured using a ConfigMap.

Recommended configuration:

- Run multiple replicas when availability requirements justify them.
- Use readiness and liveness probes appropriate to the workload.
- Configure CPU and memory requests and limits.
- Run the container as a non-root user.
- Mount configuration files from a ConfigMap when runtime configuration refresh is required.
- Use a read-only root filesystem where compatible with the workload.
- Keep application configuration separate from container image contents.

The service's `/healthz` endpoint can be used for HTTP probes. Application-specific readiness checks should reflect the actual requirements of the workload.

## Security Considerations

- The Docker image runs as a non-root user.
- The application requires no third-party Python dependencies.
- Configuration files can be mounted read-only.
- The Docker health check uses a local HTTP request.
- The base image tag is pinned, but it is not an immutable image digest.

For production deployments, consider digest pinning, image scanning, SBOM generation, signature verification, network restrictions, and automated dependency and container security checks.

## Limitations

- The service is a simple HTTP application, not a production-grade API framework.
- The `/healthz` endpoint checks HTTP responsiveness rather than downstream dependencies.
- The service does not implement authentication, authorization, or business-specific API routes.
- Projected ConfigMap changes are not instantaneous.
- No live Kubernetes deployment or test result is claimed by this README.

## AI Usage

ChatGPT assisted with drafting and reviewing the service implementation, Dockerfile, configuration behavior, and documentation. The code and deployment should be tested in the target environment before submission.

## License

Add the license required by your repository or assessment instructions.
