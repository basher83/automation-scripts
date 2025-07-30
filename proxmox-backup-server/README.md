# Proxmox Backup Server Scripts

Scripts for monitoring and checking backup health status on Proxmox Backup Server (PBS).

## pbs-backup-health.sh

A backup health monitoring script that queries the Proxmox Backup Server API to verify recent backups exist for specified VMs.

### Features

- Checks backup status for multiple VMs via PBS API
- Uses API token authentication for secure access
- Identifies VMs missing recent backups
- Lightweight monitoring using curl and jq
- Easy to integrate with monitoring systems or cron jobs

### Configuration

Before using the script, you need to configure the following variables at the top of the script:

```bash
PBS_HOST="https://pbs.local:8007"              # Your PBS server URL
TOKEN="root@pam!ci-backup-token=your-token-value"  # Your API token
VMID_LIST=("100" "101" "105")                  # List of VM IDs to monitor
```

You'll also need to update the datastore name in the API path:
```bash
/api2/json/datastore/your-datastore-name/snapshots
```

### Usage

```bash
# Run the backup health check
./pbs-backup-health.sh

# Run via cron (example: daily at 9 AM)
0 9 * * * /usr/local/sbin/pbs-backup-health.sh
```

### Requirements

- Proxmox Backup Server with API access
- `curl` for API requests
- `jq` for JSON parsing
- Valid API token with appropriate permissions

### Creating an API Token

1. Log into your Proxmox Backup Server web interface
2. Go to Configuration → Access Control → API Tokens
3. Add a new token with appropriate permissions
4. Copy the token value and update the script

### Output

The script will only produce output when a VM is missing recent backups:
```
⚠️ No recent backup for VM 105
```

No output means all specified VMs have recent backups.

### Security Notes

- Store the script with restricted permissions (e.g., `chmod 700`)
- Consider using environment variables for sensitive data
- The API token should have minimal required permissions
- Use HTTPS for secure API communication

### Integration Ideas

- Pipe output to monitoring systems (Nagios, Zabbix, etc.)
- Send alerts via email or messaging platforms
- Log results for historical tracking
- Combine with other health checks for comprehensive monitoring

### Troubleshooting

If the script isn't working:

1. Verify PBS server URL is accessible: `curl -k https://pbs.local:8007`
2. Check API token is valid and has correct permissions
3. Ensure datastore name matches your PBS configuration
4. Verify jq is installed: `which jq`
5. Test API access manually:
   ```bash
   curl -s --header "Authorization: PVEAPIToken=${TOKEN}" \
       "${PBS_HOST}/api2/json/datastore/your-datastore-name/snapshots"
   ```

### Limitations

- Only checks for backup existence, not backup integrity
- Doesn't verify backup age (just checks most recent)
- Requires manual configuration of VM IDs to monitor