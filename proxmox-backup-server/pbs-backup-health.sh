#!/bin/bash
# /usr/local/sbin/pbs-backup-health.sh

PBS_HOST="https://pbs.local:8007"
TOKEN="root@pam!ci-backup-token=your-token-value"
VMID_LIST=("100" "101" "105")

for vmid in "${VMID_LIST[@]}"; do
    curl -s --header "Authorization: PVEAPIToken=${TOKEN}" \
        "${PBS_HOST}/api2/json/datastore/your-datastore-name/snapshots?type=vm&vmid=${vmid}" |
        jq '.[0]' | grep -q '"backup-type":"vm"' || echo "⚠️ No recent backup for VM ${vmid}"
done
