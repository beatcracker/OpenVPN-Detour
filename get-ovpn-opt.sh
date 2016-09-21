#!/bin/sh

OPT_TYPE=${1:-full}
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OPENVPN_CFG="openvpn.conf"
OPTIONS_CFG="options.conf"
TMP_OPTIONS_CFG="options.tmp"

trap cleanup EXIT

cleanup() {
  rm "$TMP/$TMP_OPTIONS_CFG" 2>/dev/null
}

replace() {
  mv -f "$TMP/$TMP_OPTIONS_CFG" "$SCRIPT_DIR/$OPTIONS_CFG"
  #chmod 644 "$SCRIPT_DIR/$OPTIONS_CFG"
}

restart_ovpn() {
  killall -HUP openvpn
}

get_ovpn_options() {
  if [ "$OPT_TYPE" = 'full' ] ; then
    openvpn --cd "$SCRIPT_DIR" --config "$OPENVPN_CFG" --dev null --verb 3 \
    | grep -o -E 'PUSH_REPLY,.+?,push-continuation' \
    | awk -F "," '{for (i=2; i<NF; i++) print $i}' \
    > "$TMP/$TMP_OPTIONS_CFG"
  else
    openvpn --cd "$SCRIPT_DIR" --config "$OPENVPN_CFG" --dev null --verb 3 \
    | grep -o -E '\<route([[:space:]]{1,}([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}){2}\>' \
    > "$TMP/$TMP_OPTIONS_CFG"
  fi
}

get_ovpn_options

if [ ! -s "$TMP/$TMP_OPTIONS_CFG" ] ; then
  exit 1
fi

if [ ! -e "$SCRIPT_DIR/$OPTIONS_CFG" ] ; then
  replace
  exit $?
fi

if cmp -s "$SCRIPT_DIR/$OPTIONS_CFG" "$TMP/$TMP_OPTIONS_CFG" >/dev/null ; then
  true # nothing todo
else
  if replace ; then
	# Uncomment line below, to restart OpeVNP if new routes found
    # restart_ovpn
  fi
fi