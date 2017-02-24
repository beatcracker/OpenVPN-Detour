#!/bin/sh

#########################################################
#                    CONFIGURATION                      #
#########################################################

# Path to resolv.conf, used to apply
# DNS servers pushed by OpenVPN
RESOLV_CFG='/tmp/resolv.conf'

# Temp directory path
TEMP_DIR='/tmp'

# Output to system log?
USE_SYSLOG='1'

# Add iptables rules?
ADD_IPTABLES_RULES='1'

# Apply pushed DNS servers?
SET_DNS_SERVERS='1'

#########################################################
#              DO NOT EDIT BELOW THIS LINE              #
#########################################################

OPENVPN_CFG="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$config"
OPTIONS_CFG="${config}.detour"
TEMP_RESOLV_CFG="$(basename $RESOLV_CFG).detour"

if [ "$USE_SYSLOG" -eq '1' ]
then
  alias echo='logger -s -t OpenVPN-Detour'
fi

#########################################################

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

reconfigure_dnsmasq() {
  echo 'Reconfiguring dnsmasq'
  killall -HUP dnsmasq
}

set_dns() {
  echo 'Starting DNS setup'
  echo 'Current DNS servers:'
  echo "$(cat $RESOLV_CFG)"

  grep -v -F 'nameserver' "$RESOLV_CFG" > "$TEMP_DIR/$TEMP_RESOLV_CFG"

  if [ -z "$foreign_option_1" ]
  then
    echo "Getting new DNS servers from: $TEMP_DIR/$OPTIONS_CFG"

    grep -F 'dhcp-option DNS' "$TEMP_DIR/$OPTIONS_CFG" \
    | sed -e 's/dhcp-option DNS/nameserver/g' \
    >> "$TEMP_DIR/$TEMP_RESOLV_CFG"
  else
    echo 'Getting new DNS servers from env. variables'

    set | grep -E 'foreign_option_[[:digit:]]+=' \
    | cut -f 2 -d'=' | tr -d "'" \
    | sed -e 's/dhcp-option DNS/nameserver/g' \
    >> "$TEMP_DIR/$TEMP_RESOLV_CFG"
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
        echo "$(cat $RESOLV_CFG)"

        reconfigure_dnsmasq
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
    echo "$(cat $RESOLV_CFG)"
    reconfigure_dnsmasq
    echo 'Done'
  fi
}

get_ovpn_options() {
  echo 'Getting pushed OpenVPN configuration'
  echo "Using config file: $OPENVPN_CFG"
  echo "Using output file: $TEMP_DIR/$OPTIONS_CFG"

  echo 'Starting dummy OpenVPN process to get pushed configuration...'
  openvpn --config "$OPENVPN_CFG" --dev null --verb 3 \
  | grep -o -E 'PUSH_REPLY,.+?,push-continuation' \
  | awk -F "," '{for (i=2; i<NF; i++) print $i}' \
  > "$TEMP_DIR/$OPTIONS_CFG"

  if [ ! -s "$TEMP_DIR/$OPTIONS_CFG" ]
  then
   echo 'Failed to get pushed OpenVPN configuration'
   exit 1
  else
   echo 'Done'
  fi
}

cleanup_temp() {
 echo 'Removing temporary files'
 rm "$TEMP_DIR/$TEMP_RESOLV_CFG" "$TEMP_DIR/$OPTIONS_CFG"
 echo 'Done'
}

#########################################################

echo "Script type: $script_type"
echo "Script context: $script_context"

case "$script_type" in
  'up')
    get_ovpn_options
    ;;
  'route-up')
    if [ "$ADD_IPTABLES_RULES" -eq '1' ]
    then
	  if [ "$script_context" -eq 'restart' ]
	  then
	    echo 'Restart detected: restoring iptables'
	    set_iptables 'D'
	  fi 
      set_iptables 'I'
    else
      echo 'Skipping iptables rules insert'
    fi

    set_routes 'add'

    if [ "$SET_DNS_SERVERS" -eq '1' ]
    then
	  if [ "$script_context" -eq 'restart' ]
	  then
	    echo 'Restart detected: restoring DNS servers'
	    restore_dns
	  fi 
      set_dns
    else
      echo 'Skipping DNS servers setup'
    fi
    ;;
  'down')
    if [ "$ADD_IPTABLES_RULES" -eq '1' ]
    then
      set_iptables 'D'
    else
      echo 'Skipping iptables rules delete'
    fi

    if [ "$SET_DNS_SERVERS" -eq '1' ]
    then
      restore_dns
    else
      echo 'Skipping DNS servers restore'
    fi

    cleanup_temp

    # Not needed, OpenVPN seems to clear routes itself
    #set_routes 'del'
    ;;
  *)
    echo "Invalid script type: '$script_type'. Should be one of the following: 'up', 'down', 'route-up'"
    exit 1
    ;;
esac