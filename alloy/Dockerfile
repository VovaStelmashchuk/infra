FROM grafana/alloy:v1.9.2

COPY config.alloy /etc/alloy/config.alloy

# Alloy runs as root in the official image, which is what lets it read
# /var/run/docker.sock without extra group juggling.
CMD [ \
  "run", \
  "--server.http.listen-addr=0.0.0.0:12345", \
  "--storage.path=/var/lib/alloy/data", \
  "/etc/alloy/config.alloy" \
]
