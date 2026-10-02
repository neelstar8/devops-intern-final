# Pinned base image (never ":latest") so builds are reproducible.
# The "-slim" variant drops modules this static site does not use and keeps
# the final image comfortably under the 60 MB budget.
FROM nginx:1.27-alpine-slim

# Commit SHA injected at build time; CI passes --build-arg BUILD_SHA=${{ github.sha }}.
ARG BUILD_SHA=local
LABEL org.opencontainers.image.title="devops-intern-final" \
      org.opencontainers.image.revision="${BUILD_SHA}"

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

# Stamp the build identifier into the page, then hand ownership of the
# writable paths to the unprivileged nginx user that ships in the base image.
RUN sed -i "s|__BUILD_SHA__|${BUILD_SHA}|g" /usr/share/nginx/html/index.html \
 && chown -R 101:101 /usr/share/nginx/html /var/cache/nginx

# 101:101 is the uid:gid of the "nginx" user in the base image.
# A numeric id is used so the host can always resolve it.
USER 101:101

EXPOSE 8080

# busybox wget is already in the alpine base, so no extra packages are needed.
# --spider exits non-zero on failure, which is what Docker checks.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "--quiet", "--tries=1", "--spider", "http://127.0.0.1:8080/healthz"]

CMD ["nginx", "-g", "daemon off;"]
