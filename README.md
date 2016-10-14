# OpenVPN-Detour
Kludge for OpenVPN clients that can't handle large amount of pushed routes:

```
/sbin/ifconfig tun0 192.168.100.18 netmask 255.255.252.0 mtu 1500 broadcast 192.168.103.255
Linux ifconfig failed: could not execute external program
Exiting due to fatal error
```

This happens to the users of the Russian free anti-censorship service [AntiZapret](https://antizapret.prostovpn.org/). It pushes about 25000 routes.


# How-to

This solution is tested with Asus WL500W router: it takes about ~30 minutes to push all the routes, but afterwards it works fine.

1. Copy scripts to your router
2. Edit `detour.sh`:
2. Set path to your OpenVPN config:
	* `OPENVPN_CFG='/opt/etc/openvpn/openvpn.conf'`
3. Set path to your `resolv.conf`:
	* `RESOLV_CFG='/tmp/resolv.conf'`
3. Set path to your TEMP directory:
	* `TEMP_DIR='/tmp'`
4. Edit your OpenVPN config to include this lines:

  ```
  #### OpenVPN-Detour ####
  script-security 3
  route-nopull
  up detour.sh
  route-up detour.sh
  down detour.sh
  ########################
```

# Notes
`detour.sh` will also add `iptables` rules to allow traffic to pass beween `bridge` and OpenVPN `tunnel` interface. To disable this, comment this line on `detour.sh`:

```
  'route-up')
    #set_iptables "I"
    set_routes "add"
    set_dns
```