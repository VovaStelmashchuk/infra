FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-pip ca-certificates \
    && pip3 install --no-cache-dir awscli \
    && rm -rf /var/lib/apt/lists/*

RUN aws --version

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh
