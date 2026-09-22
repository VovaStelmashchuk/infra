FROM prometheuscommunity/postgres-exporter:v0.17.1

# The default collectors already give connections, transactions, locks and so
# on. The query timing metrics are defined by us in queries.yaml on top of
# pg_stat_statements, so the metric names stay stable and the cardinality stays
# bounded (aggregated per database + a top-N of the slowest statements).
COPY queries.yaml /etc/postgres-exporter/queries.yaml
