# Proxmox Virtual Environment Scripts

Scripts for monitoring and managing Proxmox VE backup tasks and system health.

## pve-backup-status.sh

A comprehensive backup status checker that parses Proxmox VE task logs to display recent backup job results with enhanced formatting and error analysis.

### Features

- Displays backup status for the most recent backup tasks (OK/ERROR/UNKNOWN)
- Shows detailed information for each backup job:
  - Timestamp of execution
  - Scope (single VM or all VMs)
  - VM names and IDs
  - Success/failure counts for batch jobs
  - Backup duration
- Automatic color output with terminal detection
- Efficient log parsing using ripgrep
- Support for both single VM and "all VMs" backup jobs

### Usage

```bash
# Show last 10 backup tasks (default)
./pve-backup-status.sh

# Show last 20 backup tasks
./pve-backup-status.sh 20

# Show without colors (for piping/logging)
./pve-backup-status.sh 10 --no-color
./pve-backup-status.sh --plain
```

### Requirements

- Proxmox VE installation
- Access to `/var/log/pve/tasks/` directory
- ripgrep (`rg`) for efficient log searching

### Output Example

```
Proxmox Backup Status - Last 10 Tasks
================================================
STATUS    TIMESTAMP           SCOPE        DETAILS
------------------------------------------------------------------------
✓ OK      2024-01-20 03:00:15 All VMs (5)  ✓5 ✗0 (45m)
✓ OK      2024-01-20 02:00:10 VM 101       Success (12m)
✗ ERROR   2024-01-19 03:00:14 All VMs (5)  ✓4 ✗1 (52m)
```

### Tips

The script provides helpful commands for further investigation:

- View detailed logs: `cat /var/log/pve/tasks/$HASH/$UPID`
- Monitor real-time: `tail -f /var/log/pve/tasks/active`
- Check specific VM: `rg 'vmid.*123' /var/log/pve/tasks/*/*vzdump*`
- View all errors: `rg 'ERROR:' /var/log/pve/tasks/*/*vzdump* | tail -20`
- Check backup storage: `pvesm status`

### Environment Variables

- `LOG_PATH`: Override default log path (default: `/var/log/pve/tasks`)
- `NO_COLOR`: Disable color output
- `TERM`: Automatically detected for color support

### Exit Codes

- `0`: Success
- `1`: Invalid arguments or log path not found

### Notes

- The script requires read access to Proxmox task logs
- Best run as root or with appropriate permissions
- Backup task files follow the UPID format for parsing