#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Renders the config templates for this network and runs privoxy (background) + tor (foreground).
set -eu

: "${GATEWAY_IP:?GATEWAY_IP must be set}"
case "$GATEWAY_IP" in
  *[!0-9.]*|"") echo "anonbox-gateway: invalid GATEWAY_IP '$GATEWAY_IP'" >&2; exit 64 ;;
esac

sed "s/@GATEWAY_IP@/${GATEWAY_IP}/g" /etc/anonbox/torrc.template > /tmp/torrc
sed "s/@GATEWAY_IP@/${GATEWAY_IP}/g" /etc/anonbox/privoxy.conf.template > /tmp/privoxy.conf

privoxy --no-daemon /tmp/privoxy.conf &
exec tor -f /tmp/torrc
