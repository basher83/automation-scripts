# Accepted Security Considerations (Homelab Context)

This document records security exceptions/decisions intentionally accepted for this repository's homelab usage. These items SHOULD NOT be treated as defects unless the context changes. See “Revisit when” for triggers.

Owner: basher83  
Status: Accepted  
Last updated: 2025-08-10  
Next review: 2026-02-01

## 1) SSL/TLS verification default disabled (verify_ssl: false)

- Affected:
  - `proxmox-virtual-environment/prometheus-pve-exporter/install-pve-exporter.sh` (supports `--verify-ssl` but defaults to disabled)
- Decision:
  - Keep default `VERIFY_SSL=false` and write `verify_ssl: false` in config. Runtime opt-in supported via `--verify-ssl`.
- Rationale:
  - Homelab environment with internal/self-signed certificates; reducing friction for setup and upgrades.
- Compensating controls:
  - Network isolation (trusted LAN), host-based firewalling.
  - Least-privilege service account and restricted file permissions (config/logs 640).
  - Ability to enable `--verify-ssl` per host when trusted CA is available.
- Revisit when:
  - Service is exposed outside the trusted LAN, or a managed CA (e.g., ACME) becomes standard.
  - Compliance or shared multi-tenant requirements arise.

## 2) No GPG/signature or checksum validation for internal agent downloads

- Affected:
  - `monitoring/checkmk/install-agent.sh` (downloads via HTTP from internal mirror; no GPG/checksum validation)
- Decision:
  - Continue using HTTP to internal mirror without automated GPG/checksum verification.
- Rationale:
  - Homelab-controlled mirror within trusted network; simplicity prioritized over supply-chain assurance for internal artifacts.
- Compensating controls:
  - Artifact hosting restricted to trusted admin(s); mirror not internet-exposed.
  - Basic emptiness/size checks post-download; operational monitoring during installs.
  - Optional manual verification during mirror updates (out-of-band).
- Revisit when:
  - Mirror becomes externally reachable or multi-tenant.
  - Increased supply-chain risk appetite or requirement to attest artifacts.

---

Notes:

- These decisions supersede recommendations in `SECURITY_ANALYSIS_REPORT.md` for the homelab context.
- If context changes, update this file and adjust the scripts accordingly.
