FROM grafana/loki:3.5.1

# The base image is distroless (no shell tooling, no package manager), so the
# image only carries our config. Ownership of the /loki volume is prepared by
# the loki-init service in docker-stack.yml.
COPY loki-config.yml /etc/loki/config.yml

EXPOSE 3100

CMD ["-config.file=/etc/loki/config.yml"]
