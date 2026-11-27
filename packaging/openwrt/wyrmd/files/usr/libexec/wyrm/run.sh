#!/bin/sh
# What procd runs as the service `wyrmd`, as the user `wyrm` and only on a device with
# an applied configuration: waits for the clock on the first start, then becomes the
# broker.
#
# A board without a battery starts near the build date of the image. The first start
# makes the site's CA, so it waits for NTP, at most 120 s; then it goes on (ADR 0051
# §3, "Time"). /etc/hotplug.d/ntp/20-wyrm-time writes the file this waits for.

DATA=/srv/wyrm
SYNCED=/var/run/wyrm/time-synced
WAIT_S=120

# data_dir holds the keys of the site: nobody else reads what the broker writes
umask 077
# a relative `data_dir` of a configuration lands on the data partition
cd "$DATA" || exit 1

if [ ! -d "$DATA/pki" ]; then
	waited=0
	while [ ! -e "$SYNCED" ] && [ "$waited" -lt "$WAIT_S" ]; do
		sleep 1
		waited=$((waited + 1))
	done
	if [ ! -e "$SYNCED" ]; then
		echo "wyrm: no NTP answer in $WAIT_S s: the site CA is made with the clock as it is" >&2
	fi
fi

exec /usr/bin/wyrmd -c /etc/wyrm/wyrmd.json5
