FROM telegraf:1.38.1

COPY telegraf.conf /etc/telegraf/telegraf.conf
COPY entrypoint.sh /custom-entrypoint.sh

# We run as root initially so the entrypoint can modify groups.
# The entrypoint will then drop privileges to 'telegraf' user.
USER root

ENTRYPOINT ["/custom-entrypoint.sh"]
CMD ["telegraf"]
