# Security Analysis Report for Bash Scripts

## Summary

I performed a comprehensive security analysis of all bash scripts in the automation-scripts repository. The analysis focused on:

1. Command injection vulnerabilities
2. Path traversal issues
3. Input validation and sanitization
4. Race conditions
5. Hardcoded credentials
6. Variable quoting
7. User input handling
8. File permissions
9. Use of dangerous commands (eval)
10. Temporary file handling

## Overall Assessment

The scripts demonstrate **good security practices** overall, with proper error handling, input validation, and defensive programming techniques. However, I identified several areas for improvement.

Note: Some findings are intentionally accepted for the homelab context and are documented in [Accepted Security Considerations](./SECURITY_ACCEPTED_RISKS.md). Treat those as non-actionable unless the context changes.

## Findings by Script

### 1. `/proxmox-virtual-environment/pve-backup-status.sh`

**Security Level: Good**

✅ **Strengths:**

- Proper use of `set -euo pipefail` for error handling
- Input validation for numeric arguments
- Safe use of ripgrep with proper flags
- Secure temporary file handling with cleanup trap
- No command injection vulnerabilities found
- Variables are properly quoted

⚠️ **Minor Issues:**

- Line 175-176: Date parsing from user-controllable log content could potentially fail with crafted input

  ```bash
  start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
  ```

  **Mitigation**: Already handles errors with `2>/dev/null`

  Status: Still present (low risk). Parsing failures are handled gracefully.

### 2. `/monitoring/checkmk/install-agent.sh`

**Security Level: Good**

✅ **Strengths:**

- Downloads from hardcoded URLs (no user input for URLs)
- Validates downloads are not empty
- Proper file permission handling
- Good error handling throughout

🔴 **Security Issues:**

- Line 11-14: Hardcoded URLs without HTTPS

  ```bash
  readonly AGENT_URL="http://checkmk.lab.spaceships.work/homelab/check_mk/agents/check-mk-agent_2.4.0p7-1_all.deb"
  readonly DOCKER_PLUGIN_URL="http://checkmk.lab.spaceships.work/homelab/check_mk/agents/plugins/mk_docker.py"
  ```

  **Risk**: Man-in-the-middle attacks, package tampering
  **Recommendation**: Use HTTPS URLs or implement checksum verification

  Status: Not addressed. Still using HTTP for both downloads without verification.
  Accepted (homelab): See [Accepted Security Considerations](./SECURITY_ACCEPTED_RISKS.md).

⚠️ **Medium Issues:**

- No GPG signature verification for downloaded packages
- No checksum validation of downloads

Status: Not addressed. Consider publishing and validating checksums or verifying upstream signatures.
Accepted (homelab): See [Accepted Security Considerations](./SECURITY_ACCEPTED_RISKS.md).

### 3. `/bootstrap/bootstrap.sh`

**Security Level: Very Good**

✅ **Strengths:**

- Interactive GPG key verification for eza repository
- SHA-256 checksum display for transparency
- Validates installer scripts before execution
- Proper handling of environment variables
- Safe temporary file usage

⚠️ **Minor Issues:**

- Line 269: Downloads installer from external URL

  ```bash
  UV_INSTALLER_URL="https://astral.sh/uv/install.sh"
  ```

  **Mitigation**: Script validates content and offers manual review

  Status: Present but reasonably mitigated (uses HTTPS, basic content checks, and optional interactive review).

### 4. `/nftables/open-port.sh`

**Security Level: Very Good**

✅ **Strengths:**

- Comprehensive input validation for all parameters
- Proper port range validation (1-65535)
- Protocol validation (tcp/udp only)
- Safe handling of nftables commands
- Backup creation before changes
- Dry-run mode for testing
- Backup creation before changes
- Dry-run mode for testing

✅ **Best Practices:**

- Uses parameterized commands instead of string concatenation
- Validates all user inputs before use
- Implements rollback capability

✅ **Fixes/Changes:**

- Removed `eval`; now calls `nft` with properly quoted arguments
- Added strict validation for `--table`/`--chain` (letters, numbers, underscore, hyphen)

### 5. `/proxmox-backup-server/pbs-backup-health.sh`

**Security Level: Good with Concerns**

✅ **Strengths:**

- Uses secrets management (Infisical) instead of hardcoded credentials
- Validates API responses
- Proper error handling

🔴 **Security Issues:**

- Line 91: Uses `--fail` but not `--fail-with-body`

  ```bash
  curl -s --fail --header "Authorization: PVEAPIToken=${PBS_TOKEN}" ...
  ```

  **Risk**: May miss important error information

⚠️ **Medium Issues:**

- API token passed via command line (visible in process list)
  **Recommendation**: Use curl's `--config` option or stdin

ℹ️ **Resolved/Clarified:** Uses HTTPS by default and does not specify `--insecure`; curl will perform certificate validation by default. Certificate validation is therefore enabled (subject to a valid CA chain on the host).

### 6. `/documentation/update-trees.sh`

**Security Level: Good**

✅ **Strengths:**

- Limited scope (documentation only)
- Safe file operations
- No user input processing
- Proper use of mktemp

⚠️ **Minor Issues:**

- Line 58: Tree flags could be exploited if modified

  ```bash
  local tree_flags="${3:--a -I '.git|node_modules|.DS_Store' --charset ascii}"
  ```

  **Mitigation**: Only called internally with hardcoded values

  Status: Still present (low risk in current usage). Inputs are internal and fixed.

### 7. `/proxmox-virtual-environment/prometheus-pve-exporter/install-pve-exporter.sh`

**Security Level: Good**

✅ **Strengths:**

- Creates dedicated system user with restricted shell
- Implements systemd security hardening (NoNewPrivileges, ProtectSystem)
- Secure file permissions (640) for sensitive configs
- Token values are not logged

⚠️ **Medium Issues:**

- Line 141: `verify_ssl: false` in configuration

  ```yaml
  verify_ssl: false
  ```

  **Risk**: Susceptible to MITM attacks
  **Recommendation**: Use proper certificates and enable SSL verification

  Status: Partially addressed. Script now supports `--verify-ssl` to enable verification, but the default remains `false`.
  Accepted default (homelab): See [Accepted Security Considerations](./SECURITY_ACCEPTED_RISKS.md).

### 8. `/consul/prometheus/prometheus-consul-exporter.sh`

**Security Level: Very Good**

✅ **Strengths:**

- Excellent secret management with Infisical
- Comprehensive input validation
- Secure token handling (never displayed)
- Proper file permissions
- Good error messages without exposing sensitive data

⚠️ **Minor Issues:**

- Token passed to Netdata config file in plain text (necessary for operation)

Status: Still present (by design of the Netdata Consul collector). File permissions are set to 640.

## General Security Recommendations

### 1. **Certificate Validation**

- One script (`prometheus-pve-exporter`) defaults to `verify_ssl: false`; enable verification or pass `--verify-ssl`.
- Other scripts either use HTTP (no TLS) or rely on curl’s default TLS verification when using HTTPS.

Recommended actions:

- Installing proper CA certificates
- Using certificate pinning for known hosts
- At minimum, documenting the security implications

Homelab exception: Default `verify_ssl: false` for the PVE exporter is accepted. See [Accepted Security Considerations](./SECURITY_ACCEPTED_RISKS.md).

### 2. **Download Verification**

Scripts that download files should implement:

- HTTPS URLs instead of HTTP
- GPG signature verification
- SHA256 checksum validation
- Content validation before execution

Homelab exception: Internal CheckMK downloads over HTTP without GPG/checksum validation are accepted. See [Accepted Security Considerations](./SECURITY_ACCEPTED_RISKS.md).

### 3. **Secret Management**

- Avoid passing secrets via command line arguments (visible in ps)
- Use environment variables or config files with restricted permissions
- Consider using systemd's LoadCredential for service secrets

### 4. **Logging**

- Ensure sensitive information is never logged
- Set appropriate permissions on log files (640 or more restrictive)
- Implement log rotation

### 5. **Network Security**

- Prefer HTTPS/TLS for API communications (or add strong integrity checks when using HTTP on trusted LANs)
- Implement timeout values for network operations
- Consider implementing retry logic with exponential backoff

## Positive Security Practices Observed

1. **Consistent use of `set -euo pipefail`** - Ensures scripts fail safely
2. **Proper input validation** - All user inputs are validated
3. **Safe variable quoting** - Variables are properly quoted throughout
4. **No use of `eval`** - No dangerous command evaluation
5. **Secure temporary file handling** - Using mktemp with cleanup traps
6. **Proper error handling** - Comprehensive error messages without exposing secrets
7. **Interactive confirmations** - Important operations require user confirmation
8. **Backup mechanisms** - Critical changes create backups first
9. **Dry-run modes** - Allow testing without making changes
10. **Least privilege** - Services run as dedicated users

## Conclusion

The bash scripts in this repository demonstrate a strong security posture with proper defensive programming practices. The main areas for improvement are:

1. Prefer HTTPS over HTTP for downloads in `monitoring/checkmk/install-agent.sh` or add strong checksum/signature verification
2. Implement download verification (checksums/signatures) where missing
3. Avoid passing secrets in command line arguments (e.g., curl headers) to reduce exposure in process listings
4. Consider enabling SSL/TLS certificate verification by default in `prometheus-pve-exporter` when feasible

None of the identified issues represent critical vulnerabilities that would allow immediate system compromise. The scripts follow bash security best practices and show careful attention to input validation and error handling.

## Risk Summary

- **Critical Issues**: 0
- **High Risk Issues**: 2 (HTTP downloads without verification x2)
- **Medium Risk Issues**: 4 (missing GPG/checksum verification; default `verify_ssl: false`; secrets in CLI)
- **Low Risk Issues**: 5 (minor validation and robustness improvements)

Overall Risk Level: **LOW to MEDIUM** - The scripts are production-ready with clear, contained hardening items.

Note: Items marked “Accepted (homelab)” in sections above are documented in [Accepted Security Considerations](./SECURITY_ACCEPTED_RISKS.md) and are not action items unless the environment or requirements change.
