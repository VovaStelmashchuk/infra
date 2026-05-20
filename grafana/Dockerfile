FROM grafana/grafana:13.1.0-25893932881-ubuntu

ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=haohanyang-mongodb-datasource

RUN grafana-cli --pluginUrl https://github.com/haohanyang/mongodb-datasource/releases/download/v0.4.1/haohanyang-mongodb-datasource-0.4.1.zip plugins install haohanyang-mongodb-datasource
