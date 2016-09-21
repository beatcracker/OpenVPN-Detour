# OpenVPN-Detour
Kludge for OpenVPN clients that can't handle large amount of pushed routes:

```
/sbin/ifconfig tun0 192.168.100.18 netmask 255.255.252.0 mtu 1500 broadcast 192.168.103.255
Linux ifconfig failed: could not execute external program
Exiting due to fatal error
```

Happens to the users of the Russian free anti-censorship service [AntiZapret](https://antizapret.prostovpn.org/). It pushes about 25000 routes.


# How-to

This solution is tested with Asus WL500W router: it takes about 1 hour to push all the routes, but afterwards it works fine.

1. Copy scripts to your OpenVPN config directory
2. Change your OpenVPN config name in `get-ovpn-opt.sh`:
	* `OPENVPN_CFG="your-config-name.conf"`
3. Edit your OpenVPN config to include this:

  ```
  #### OpenVPN-Detour ####
  script-security 3
  route-nopull
  up routes.sh
  down routes.sh
  route-up routes.sh
  #######################
```

4. Run `get-ovpn-opt.sh` once. It should dump all pushed options (including routes) to `options.conf`
5. Now, the next time you start OpenVPN client, it will use `routes.sh` to push routes from `options.conf`
6. Optionally, add `get-ovpn-opt.sh` to your cron, to update routes periodically
7. If you whant to reconnect OpenVPN if new routes are found, uncomment one line in `get-ovpn-opt.sh`:

  ```
  if replace ; then
    # Uncomment line below, to restart OpeVNP if new routes found
    # restart_ovpn
  fi
  ```

# Notes
`routes.sh` will also add `iptables` rules to allow traffic to pass beween `bridge` and OpenVPN `tunnel` interface. To disable this, remove/comment this lines from your OpenVPN config:

```
up routes.sh
down routes.sh
```