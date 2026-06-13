FROM mongo:8.2.5

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-pip ca-certificates \
    && pip3 install --no-cache-dir --break-system-packages awscli \
    && rm -rf /var/lib/apt/lists/*

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh
