#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OPTIONS_CFG="options.conf"

set_iptables() {
  iptables -"$1" FORWARD -i br0 -o "$dev" -j ACCEPT
  iptables -"$1" FORWARD -i "$dev" -o br0 -j ACCEPT
  iptables -"$1" INPUT -i "$dev" -j ACCEPT
  iptables -t nat -"$1" POSTROUTING -o "$dev" -j MASQUERADE
}

set_routes() {
  # Hack: https://community.openvpn.net/openvpn/ticket/668
  route_vpn_gateway=$(awk '/^route-gateway/ {print $2 ; exit}' \
  "$SCRIPT_DIR/$OPTIONS_CFG")

  # Pushing so much routes takes a long time. We ping VPN
  # server in background, so it doesn't restart connection.
  ping -q $route_vpn_gateway &

  awk -v CMD="$1" -v GW="$route_vpn_gateway" \
  '/^route / {if($3==""){$3="255.255.255.255"} ; system(sprintf("%s %s -net %s netmask %s gw %s",$1,CMD,$2,$3,GW))}' \
  "$SCRIPT_DIR/$OPTIONS_CFG"

  # Stop pinging VPN server
  killall ping
}

case "$script_type" in
  'up')
    set_iptables "I"
    ;;
  'down')
    set_iptables "D"
    # Not needed, OpenVPN seems to clear routes itself
    #set_routes "del"
    ;;
  'route-up')
    set_routes "add"
    ;;
  *)
    echo "Invalid script type: '$script_type'. Should be one of the following: 'up', 'down', 'route-up'"
    exit
    ;;
esac