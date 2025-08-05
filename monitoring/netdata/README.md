# Netdata Parent-Child Architecture Configuration

This directory contains configuration files and scripts for managing a Netdata parent-child architecture with high availability and mutual replication.

## Architecture Overview

Our Netdata setup uses a hierarchical parent-child architecture with the following components:

### Parent Nodes (Proxmox Hosts)

- **lloyd** - Primary parent accepting child streams
  - GUID: e6635edf-68f9-4cfa-8aa9-338d649e4e72
  - Management: 192.168.10.2 (2.5G)
  - Application: 192.168.11.2 (10G) - Used for Netdata streaming
- **holly** - Secondary parent with mutual replication
  - GUID: fe51dda8-238b-4396-983b-58c08dffe196
  - Management: 192.168.10.3 (2.5G)
  - Application: 192.168.11.3 (10G) - Used for Netdata streaming
- **mable** - Tertiary parent accepting child streams
  - GUID: 80cf055f-4961-4376-bdbf-bbee6d77959c
  - Management: 192.168.10.4 (2.5G)
  - Application: 192.168.11.4 (10G) - Used for Netdata streaming
- **pve1** - Proxmox Host
  - GUID: 9e2a0012-9cd3-42d7-b82a-afa595b3e44c
  - Management/Application: 192.168.30.50 (2.5G)

### Child Nodes

#### Nomad Cluster (VMs)

All Nomad nodes have dual interfaces - streaming happens over 10G network:

- **nomad-server-1**
  - GUID: 524f3f9f-0140-427d-922d-bad37427a825
  - Management: 192.168.10.11 (2.5G)
  - Application: 192.168.11.11 (10G) - Used for Netdata streaming
- **nomad-server-2**
  - Management: 192.168.10.12 (2.5G)
  - Application: 192.168.11.12 (10G) - Used for Netdata streaming
- **nomad-server-3**
  - Management: 192.168.10.13 (2.5G)
  - Application: 192.168.11.13 (10G) - Used for Netdata streaming
- **nomad-client-1**
  - GUID: 3fd08a42-2a50-46a1-9634-f69bd9b16ab1
  - Management: 192.168.10.20 (2.5G)
  - Application: 192.168.11.20 (10G) - Used for Netdata streaming
- **nomad-client-2**
  - Management: 192.168.10.21 (2.5G)
  - Application: 192.168.11.21 (10G) - Used for Netdata streaming
- **nomad-client-3**
  - Management: 192.168.10.22 (2.5G)
  - Application: 192.168.11.22 (10G) - Used for Netdata streaming

#### Other Nodes (192.168.30.0/24 subnet)

- **dockervm** (192.168.30.x)
- **proxmoxt430** (192.168.30.x)
- **pve1** (192.168.30.x)
- **pbs** (192.168.30.x) - Proxmox Backup Server
- **mac-studio** (192.168.30.x) - Personal machine

## Configuration Files

### Parent Node Configuration

Each parent node requires two main configuration files:

1. **stream.conf** - Defines streaming relationships
2. **netdata.conf** - Configures data retention and storage

#### Lloyd (Primary Parent) 192.168.11.2

```ini
# /etc/netdata/stream.conf
[stream]
    enabled = no  # Not streaming to another parent (will be enabled for replication)

[nomad-cluster-api-key]
    enabled = yes
    # Accept connections from Nomad nodes on 10G network
    allow from = 192.168.11.11 192.168.11.12 192.168.11.13 192.168.11.20 192.168.11.21 192.168.11.22
    db = dbengine
    health enabled = yes
    postpone alarms on connect = 60s

[parent-replication-key]
    enabled = yes
    # Accept replication from other parents on 10G network
    allow from = 192.168.11.3 192.168.11.4
    db = dbengine
```

### Child Node Configuration

Child nodes stream metrics to all parent nodes via the 10G network for high availability:

```ini
# /etc/netdata/stream.conf
[stream]
    enabled = yes
    # Use 10G network IPs for streaming
    destination = 192.168.11.2:19999 192.168.11.3:19999 192.168.11.4:19999
    api key = nomad-cluster-api-key
    timeout seconds = 60
    buffer size bytes = 1048576
    reconnect delay seconds = 5
    initial clock resync iterations = 60
    send charts matching = *
```

## API Keys

We use two API keys for different purposes:

1. **nomad-cluster-api-key** - Used by child nodes to stream to parent nodes
2. **parent-replication-key** - Used for mutual replication between parent nodes

## Mutual Replication Setup

To enable full mutual replication between all three parent nodes using the 10G network:

### Holly → Lloyd & Mable

```ini
[stream]
    enabled = yes
    # Replicate to other parents via 10G network
    destination = 192.168.11.3:19999 192.168.11.4:19999
    api key = parent-replication-key
```

### Lloyd → Holly & Mable

```ini
[stream]
    enabled = yes
    # Replicate to other parents via 10G network
    destination = 192.168.11.2:19999 192.168.11.4:19999
    api key = parent-replication-key
```

### Mable → Holly & Lloyd

```ini
[stream]
    enabled = yes
    # Replicate to other parents via 10G network
    destination = 192.168.11.2:19999 192.168.11.3:19999
    api key = parent-replication-key
```

## Installation Scripts

See the `scripts/` directory for automated installation and configuration scripts.

## Network Configuration

### Binding to Specific Interfaces

To ensure Netdata uses the 10G network, configure the bind address in `netdata.conf`:

```ini
# On parent nodes - bind to 10G interface
[web]
    bind to = 192.168.11.2:19999  # For holly (adjust IP for each host)

# Or bind to all interfaces but use firewall rules
[web]
    bind to = *:19999
```

### Firewall Rules

Allow Netdata traffic on the 10G network:

[TODO]: These devices use nftables not ufw/iptables.

```bash
# UFW example - allow from 10G network
sudo ufw allow from 192.168.11.0/24 to any port 19999

# iptables example
sudo iptables -A INPUT -p tcp --dport 19999 -s 192.168.11.0/24 -j ACCEPT
```

## Best Practices

1. **High Availability**: Configure children to connect to all parent nodes
2. **Data Retention**: Ensure all parents have identical retention settings
3. **Resource Planning**: Each parent will store all metrics from all children
4. **Network Security**: Use firewall rules to restrict access to streaming ports
5. **Monitoring**: Check `/var/log/netdata/error.log` for connection issues
6. **Network Optimization**: Use 10G network for streaming to minimize impact on management network

## Troubleshooting

### Verify Child-to-Parent Connection

```bash
# On parent node
grep "new client" /var/log/netdata/error.log

# On child node
grep "established communication" /var/log/netdata/error.log
```

### Check Streaming Status

```bash
# See all connected children on a parent
curl -s http://localhost:19999/api/v1/info | jq '.stream'
```

### Common Issues

1. **Connection Refused**: Check firewall rules for port 19999
2. **API Key Mismatch**: Verify the API key matches between child and parent
3. **Data Gaps**: Ensure proper clock synchronization (NTP)
4. **High Memory Usage**: Adjust retention settings in netdata.conf

## Network Diagram

```text
                    ┌─────────────────┐
                    │     Holly       │
                    │ Mgmt: 10.2      │
                    │ 10G:  11.2      │
                    │   (Parent)      │
                    └────────┬────────┘
                             │ 10G Network
                             │ (Streaming)
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│     Lloyd       │  │     Mable       │  │  Other Subnet   │
│ Mgmt: 10.3      │  │ Mgmt: 10.4      │  │ 192.168.30.0/24 │
│ 10G:  11.3      │  │ 10G:  11.4      │  │   (Optional)    │
│   (Parent)      │  │   (Parent)      │  └─────────────────┘
└─────────────────┘  └─────────────────┘
        │                    │
        │     10G Network    │
        │    (Replication)   │
        └────────────────────┘
                    │
                    │ 10G Network
                    │ (Streaming)
    ┌───────────────┼───────────────────────────┐
    │               │                           │
    ▼               ▼                           ▼
┌─────────┐   ┌─────────┐              ┌─────────┐
│ Nomad   │   │ Nomad   │              │ Other   │
│ Servers │   │ Clients │              │ Nodes   │
│ 11.11-13│   │ 11.20-22│              │ 30.x    │
└─────────┘   └─────────┘              └─────────┘

Legend:
- Mgmt: Management network (2.5G) - 192.168.10.0/24
- 10G: Application network (10G) - 192.168.11.0/24
- Streaming: Netdata metrics streaming path
```
