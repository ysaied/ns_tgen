# Network Namespace Traffic Generator (ns_tgen)

A lightweight shell script to create network namespaces, simulate client-server traffic, and run simple services (HTTP, DNS, Syslog) within namespaces. Useful for testing network setups or traffic flows entirely on a single Linux host.

## Features

- Create client and server namespaces with either **routed (L3)** or **bridged (L2)** mode.
- Launch lightweight services in server namespaces:
  - HTTP server (lighttpd) serving a simple index page.
  - DNS server (dnsmasq) with a wildcard entry to respond with a fixed IP.
  - Syslog server (rsyslogd) listening on UDP 514 (logs discarded).
- Generate continuous traffic from client namespaces:
  - `ping` floods to server IPs.
  - `curl` HTTP requests.
  - `logger` syslog messages.
- One-command install of required host packages (`lighttpd`, `dnsmasq`, `rsyslog`).
- Easy start/stop via `--start`/`--delete` flags.
- **MIT License**—free to use and contribute!

## Requirements

- Linux with support for network namespaces (`ip netns`).
- Root privileges (or sudo) to create namespaces and install packages.
- `bash`, `ip`, `apt-get`, `lighttpd`, `dnsmasq`, `rsyslogd`.

## Usage

```bash
# Clone or download this script to your host machine
chmod +x ns_tgen.sh

# Start namespaces in routed (L3) mode and launch services:
sudo ./ns_tgen.sh --start --routed

# Start namespaces in bridged (L2) mode:
sudo ./ns_tgen.sh --start --bridged

# Delete all namespaces and cleanup:
sudo ./ns_tgen.sh --delete
```

For more details on flags:

```bash
./ns_tgen.sh --help
```
