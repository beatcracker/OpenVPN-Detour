#!/bin/sh

#########################################################
#                    CONFIGURATION                      #
#########################################################

# Path to OpenVPN config
OPENVPN_CFG='/opt/etc/openvpn/openvpn.conf'

# Path to resolv.conf, used to apply
# DNS servers pushed by OpenVPN
RESOLV_CFG='/tmp/resolv.conf'

# Temp directory path
TEMP_DIR='/tmp'

#########################################################
#              DO NOT EDIT BELOW THIS LINE              #
#########################################################

OPTIONS_CFG='detour.conf'
TEMP_RESOLV_CFG='resolv.conf.detour'

set_iptables() {
  echo "Configuring iptables. Command: '$1'"

  iptables -"$1" FORWARD -i br0 -o "$dev" -j ACCEPT
  iptables -"$1" FORWARD -i "$dev" -o br0 -j ACCEPT
  iptables -"$1" INPUT -i "$dev" -j ACCEPT
  iptables -t nat -"$1" POSTROUTING -o "$dev" -j MASQUERADE

  echo 'Done'
}

set_routes() {
  echo "Configuring routes. Command: '$1'"
  echo "Using file: $TEMP_DIR/$OPTIONS_CFG"

  # Hack: https://community.openvpn.net/openvpn/ticket/668
  route_vpn_gateway=$(awk '/^route-gateway/ {print $2 ; exit}' \
  "$TEMP_DIR/$OPTIONS_CFG")

  echo "VPN gateway: $route_vpn_gateway"

  # In case we push many routes and it takes a long time:
  # ping VPN server in background, so it doesn't restart connection.

  echo 'Starting background ping of VPN gateway...'
  ping -q $route_vpn_gateway &

  echo "Adding routes, this could take a while..."
    awk -v CMD="$1" -v GW="$route_vpn_gateway" \
    '/^route / {if($3==""){$3="255.255.255.255"};printf("%s %s -net %s netmask %s gw %s\n",$1,CMD,$2,$3,GW)}' \
    "$TEMP_DIR/$OPTIONS_CFG" \
    | sh

  echo 'Done, stopping background ping'
  killall ping
}

hup_dnsmasq() {
  echo 'Reconfiguring dnsmasq'
  killall -HUP dnsmasq
}

set_dns() {
  echo 'Starting DNS setup'
  echo 'Current DNS servers:'
  cat $RESOLV_CFG

  if [ -z "$foreign_option_1" ]
  then
    echo "Getting new DNS servers from: $TEMP_DIR/$OPTIONS_CFG"

    grep -E 'dhcp-option DNS' "$TEMP_DIR/$OPTIONS_CFG" \
    | sed -e 's/dhcp-option DNS/nameserver/g' \
    > "$TEMP_DIR/$TEMP_RESOLV_CFG"
  else
    echo 'Getting new DNS servers from env. variables'

    set | grep -E 'foreign_option_[[:digit:]]+=' \
    | cut -f 2 -d'=' | tr -d "'" \
    | sed -e 's/dhcp-option DNS/nameserver/g' \
    > "$TEMP_DIR/$TEMP_RESOLV_CFG"
  fi

  if [ -s "$TEMP_DIR/$TEMP_RESOLV_CFG" ]
  then
    echo "Backing up resolv.conf: $RESOLV_CFG -> $RESOLV_CFG.bak"
    if mv -f "$RESOLV_CFG" "$RESOLV_CFG.bak" > /dev/null
    then
      echo "Updating resolv.conf: $TEMP_DIR/$TEMP_RESOLV_CFG -> $RESOLV_CFG"
      if mv -f "$TEMP_DIR/$TEMP_RESOLV_CFG" "$RESOLV_CFG" > /dev/null
      then
        echo 'New DNS servers:'
        cat $RESOLV_CFG

        hup_dnsmasq
        echo 'Done'
      fi
    fi
  else
   echo 'No pushed DNS servers found'
  fi
}

restore_dns() {
  echo "Restoring DNS servers: $RESOLV_CFG.bak -> $RESOLV_CFG"

  if mv -f "$RESOLV_CFG.bak" "$RESOLV_CFG" > /dev/null
  then
    echo 'Restored DNS servers:'
    cat $RESOLV_CFG
    hup_dnsmasq
    echo 'Done'
  fi
}

get_ovpn_options() {
  echo 'Starting dummy OpenVPN process to get pushed configuration...'
  echo "Using config file: $OPENVPN_CFG"
  echo "Using output file: $TEMP_DIR/$OPTIONS_CFG"

  openvpn --config "$OPENVPN_CFG" --dev null --verb 3 \
  | grep -o -E 'PUSH_REPLY,.+?,push-continuation' \
  | awk -F "," '{for (i=2; i<NF; i++) print $i}' \
  > "$TEMP_DIR/$OPTIONS_CFG"

  if [ ! -s "$TEMP_DIR/$OPTIONS_CFG" ]
  then
   echo 'Failed to get OpenVPN configuration'
   exit 1
  else
   echo 'Done'
  fi
}

cleanup_temp() {
 echo 'Removing temporary files'
 rm "$TEMP_DIR/$TEMP_RESOLV_CFG"
 echo 'Done'
}

case "$script_type" in
  'up')
    get_ovpn_options
    ;;
  'down')
    set_iptables "D"
    restore_dns
    cleanup_temp
    # Not needed, OpenVPN seems to clear routes itself
    #set_routes "del"
    ;;
  'route-up')
    set_iptables "I"
    set_routes "add"
    set_dns
    ;;
  *)
    echo "Invalid script type: '$script_type'. Should be one of the following: 'up', 'down', 'route-up'"
    exit
    ;;
esac
