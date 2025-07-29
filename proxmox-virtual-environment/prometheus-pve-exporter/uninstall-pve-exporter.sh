#!/bin/bash
# uninstall-pve-exporter.sh

systemctl stop prometheus-pve-exporter
systemctl disable prometheus-pve-exporter
rm -f /etc/systemd/system/prometheus-pve-exporter.service
systemctl daemon-reload
rm -rf /opt/prometheus-pve-exporter
pveum user delete prometheus@pve
userdel prometheus
rm -rf /var/lib/prometheus
rm -rf /etc/prometheus
echo "Prometheus PVE Exporter has been removed"