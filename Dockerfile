# ch.4 - run the app in a container.
#
# Build:  docker build -t notes-app .
# Run:    docker run --rm -p 8000:8000 notes-app
#
# The same code that runs locally with `make run` now runs inside this
# image. The Dockerfile deliberately mirrors the local setup - uv + the
# lockfile - so "works locally" and "works in the container" mean the
# same thing.

# uv's official Python image: Python 3.12 + uv, so no pip/apt dance at all.
FROM astral/uv:python3.12-bookworm@sha256:9aa60c50016c0485636ab9a830246a6ef3399aa4a8bab3d17ef4a2358fba2ca7

# The app runs as this unprivileged user - a habit ch.4 installs early.
# -m -d /app makes /app its home; WORKDIR below then uses it, and it is
# writable, which matters: the app writes notes.db there (ch.5 mounts a
# volume here).
RUN groupadd -g 65532 courseuser && \
    useradd -u 65532 -g courseuser -m -d /app -s /sbin/nologin courseuser

USER 65532
WORKDIR /app

# --- Dependency layer (cached) ------------------------------------------
# Only the manifest and lockfile live here, so this layer is rebuilt only
# when you `uv add`/`uv remove` something - not when you edit app code.
# --frozen means "install exactly what uv.lock says, no re-resolution".
COPY uv.lock pyproject.toml ./
RUN uv sync --frozen --no-install-project

# The package itself (`uv sync` installed it as an editable local dep, so
# ch.4's image rebuild picks up every code change at this step).
COPY notes_app/ ./notes_app/

# Assets are *not* inside the package - main.py finds templates/ & static/
# as siblings of notes_app/ (repo root, and here, /app). COPYing them at
# the image root is exactly what keeps the path resolution local and in-
# container identical.
COPY templates/ ./templates/
COPY static/ ./static/

# Finish the editable install (links /app/notes_app into the venv).
RUN uv sync --frozen

# ch.9: the liveness probe, in the artifact itself. curl ships with the
# base image (it does NOT with alpine-slim variants - a common gotcha),
# and /health is the cheapest honest check: "the HTTP server answers".
# The readiness version (checks the DB) is the docs/09 stretch exercise.
# The compose `healthcheck:` in ch.5's file can point at the SAME
# endpoint, so `depends_on: service_healthy` becomes reliable.
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
    CMD curl -sf http://127.0.0.1:8000/health || exit 1

# Bind 0.0.0.0, not 127.0.0.1: inside a container "localhost" is the
# container's own loopback - the outside world can only reach 0.0.0.0.
CMD ["uv", "run", "--no-sync", "uvicorn", "notes_app.main:app", "--host", "0.0.0.0", "--port", "8000"]
