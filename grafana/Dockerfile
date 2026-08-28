FROM grafana/grafana:12.4.0-22081664032-ubuntu

ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=haohanyang-mongodb-datasource

RUN grafana-cli --pluginUrl https://github.com/haohanyang/mongodb-datasource/releases/download/v0.4.1/haohanyang-mongodb-datasource-0.4.1.zip plugins install haohanyang-mongodb-datasource

# Loki datasource and the "Service logs" dashboard are provisioned from files,
# so they survive a Grafana restore from backup and stay in sync with the repo.
COPY provisioning /etc/grafana/provisioning
COPY dashboards /etc/grafana/dashboards
