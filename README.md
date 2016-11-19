# OpenVPN-Detour
Kludge for OpenVPN clients that can't handle large amount of pushed routes:

```
/sbin/ifconfig tun0 192.168.100.18 netmask 255.255.252.0 mtu 1500 broadcast 192.168.103.255
Linux ifconfig failed: could not execute external program
Exiting due to fatal error
```

This happens to the users of the Russian free anti-censorship service [AntiZapret](https://antizapret.prostovpn.org/): it pushes about 25000 routes.

# Details

For every pushed route, OpenVPN [creates environment variable](https://community.openvpn.net/openvpn/wiki/Openvpn23ManPage#lbAU) `route_{parm}_{n}`, that is set prior to `--up` script execution. If the amount of routes is high, OpenVPN hits the maximum stack size limit for the process ([RLIMIT_STACK](http://www.delorie.com/gnu/docs/glibc/libc_448.html)) which [makes it segfault](https://twitter.com/ValdikSS/status/778695590997741568). This can be mitigated by setting higher limit in the [limits.conf](https://linux.die.net/man/5/limits.conf) or by running `ulimit -s 16000`. Unfortunately, none of the solutions above worked for me, since my options are pretty limited: I'm running an OpenVPN client on a router made in the past decade.

To workaround this issue, one has to disable pushed routes using `route-nopull` in the config file and then apply the routes by some other means. So OpenVPN-Detour was born.

When OpenVPN client executes `detour.sh` script, second, dummy OpenVPN connection is initiated. The script then grabs pushed configuration from the OpenVPN's debug output, extracts routes and DNS options using core Linux tools like awk/sed/grep and applies them.

# Usage

This solution is tested with Asus WL-500W router. It takes less then 10 minutes to push all the routes this way.

1. Copy script to your OpenVPN config directory
2. Make it executable:
	* `chmod +x /path/to/detour.sh`
3. Edit `detour.sh` and:
	* set path to your `resolv.conf`: `RESOLV_CFG='/tmp/resolv.conf'`
	* set path to your TEMP directory: `TEMP_DIR='/tmp'`
	* configure [syslog support](#syslog-support): `USE_SYSLOG='1'`
	* configure [iptables rules](#iptables-rules)</sup>: `ADD_IPTABLES_RULES='1'`
	* configure [DNS servers](#dns-servers): `SET_DNS_SERVERS='1'`
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

## Syslog support
If set to `1`, the script will additionaly output log to `syslog`. For routers, this means that script execution process will be shown in your router's log in web UI.

## Iptables rules
Useful for routers: add `iptables` rules to allow traffic to pass beween `bridge` and OpenVPN `tunnel` interface. Set variable to `0`, to disable this.

## DNS servers
Set variable to `0`, to ignore pushed DNS servers.
