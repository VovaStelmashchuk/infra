FROM grafana/grafana:12.4.0-22081664032-ubuntu

ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=haohanyang-mongodb-datasource

RUN grafana-cli --pluginUrl https://github.com/haohanyang/mongodb-datasource/releases/download/v0.4.1/haohanyang-mongodb-datasource-0.4.1.zip plugins install haohanyang-mongodb-datasource
