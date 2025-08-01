# Netdata Script Updates for 10G Network

## Summary of Changes

All scripts have been updated to support the dual-network architecture with streaming over the 10G network (192.168.11.0/24).

### install-netdata-parent.sh

**New Features:**

- Added `--bind-ip` option to bind Netdata to specific IP address (e.g., 10G interface)
- Updated examples to use 10G network IPs
- Enhanced display summary to show bind IP configuration
- Configuration file now properly sets the bind address in `[web]` section

**Example Usage:**

```bash
sudo ./scripts/install-netdata-parent.sh \
    --hostname holly \
    --bind-ip 192.168.11.2 \
    --peers "192.168.11.3,192.168.11.4" \
    --children "192.168.11.11 192.168.11.12 192.168.11.13 192.168.11.20 192.168.11.21 192.168.11.22" \
    --api-key "nomad-cluster-api-key" \
    --replication-key "parent-replication-key" \
    --retention 30
```

### install-netdata-child.sh

**Updates:**

- All examples now use 10G parent IPs (192.168.11.2-4)
- Documentation reflects streaming over 10G network
- Connectivity checks validate parent nodes are reachable

**Example Usage:**

```bash
sudo ./scripts/install-netdata-child.sh \
    --parents "192.168.11.2,192.168.11.3,192.168.11.4" \
    --api-key "nomad-cluster-api-key" \
    --consul \
    --docker
```

### configure-parent-replication.sh

**Updates:**

- Examples use 10G network IPs for node and peer configurations
- Properly handles mutual replication over 10G network

**Example Usage:**

```bash
sudo ./scripts/configure-parent-replication.sh \
    --node-ip 192.168.11.2 \
    --peer-ips "192.168.11.3,192.168.11.4" \
    --replication-key "parent-replication-key"
```

### check-netdata-status.sh

No changes needed - this script works with any network configuration.

## Network Configuration

### Parent Nodes

- Holly: 192.168.11.2:19999
- Lloyd: 192.168.11.3:19999
- Mable: 192.168.11.4:19999

### Child Nodes

- Nomad Servers: 192.168.11.11-13
- Nomad Clients: 192.168.11.20-22

### Benefits

1. **Performance**: 10G network provides ample bandwidth for streaming
2. **Isolation**: Monitoring traffic separated from management operations
3. **Scalability**: Room to grow without network bottlenecks
4. **Flexibility**: Scripts support both specific binding and all-interface binding

## Validation

All scripts have been:

- Updated to support 10G network configuration
- Validated for syntax errors
- Fixed for Unix line endings
- Tested for proper option parsing
