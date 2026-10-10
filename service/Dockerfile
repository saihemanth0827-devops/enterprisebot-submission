# Compile-check in a separate build stage; runtime contains only the app source.
FROM python:3.12.7-slim-bookworm AS builder
WORKDIR /build
COPY app.py ./app.py
RUN python -m py_compile app.py

FROM python:3.12.7-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    CONFIG_DIR=/etc/demo-config
WORKDIR /app
RUN groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid app --home-dir /nonexistent --shell /usr/sbin/nologin app && \
    mkdir -p /etc/demo-config && chown -R app:app /app
COPY --from=builder --chown=app:app /build/app.py /app/app.py
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"
CMD ["python", "/app/app.py"]
