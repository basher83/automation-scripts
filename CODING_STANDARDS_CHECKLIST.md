# Coding Standards Compliance Checklist

## 🚀 Quick Start Instructions

### For Developers

1. Copy this checklist to your working directory with timestamp:

   ```bash
   cp CODING_STANDARDS_CHECKLIST.md bootstrap/checklist-$(date +%Y%m%d_%H%M%S).md
   ```

2. Fill out the modification summary below
3. Check only the relevant sections for your change
4. Complete your implementation and testing
5. Submit with your pull request

### For Senior Developers/Reviewers

1. Use the developer's submitted checklist
2. Complete the "Senior Developer/Reviewer Section" at the bottom
3. Provide feedback based on your review

---

## 📝 Modification Summary

**Date:** `YYYY-MM-DD`  
**Developer:** `Your Name`  
**Script:** `script-name.sh`  

### What am I modifying?

<!-- Brief description of the change -->

### Why am I modifying it?

<!-- Reason/ticket/request -->

### Installation Instructions

<!-- Paste the minimal official installation steps for Ubuntu/Debian -->

```bash
# Example:
# sudo apt-get install package-name
# OR
# curl -fsSL https://example.com/install.sh | bash
```

**Official Docs:** `paste link here`

---

## ✅ Essential Checks (Always Required)

### Before Starting

- [ ] I've read the modification summary above
- [ ] I have the official installation docs
- [ ] I know if this needs logging (installs/system changes = YES)

### Script Header

- [ ] Has proper error handling: `set -euo pipefail`
- [ ] Has error trap: `trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR`

### For Tool Installations (bootstrap.sh, install scripts)

- [ ] Check if tool already installed before installing
- [ ] Non-interactive mode support (environment variables)
- [ ] Success/failure messages are clear
- [ ] Idempotent (safe to run multiple times)

---

## 📊 Logging (Required for Installations/System Changes)

If your script installs software or changes the system:

- [ ] Log file defined with timestamp:

  ```bash
  LOG_FILE="/var/log/scriptname-action-$(date +%Y%m%d_%H%M%S).log"
  ```

- [ ] User notified of log location at start: `print_info "Log file: $LOG_FILE"`
- [ ] Logging functions write to both console AND file
- [ ] Log location shown on error/success

---

## 🔍 Only If Applicable

### Remote Execution (if script will be run via curl)

- [ ] No relative paths used
- [ ] Environment variables for configuration
- [ ] Works when piped from curl

### Colors (if using colored output)

- [ ] Terminal color detection: `[[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]`
- [ ] NO_COLOR environment variable respected

### Cleanup (if using temp files)

- [ ] mktemp for temporary files
- [ ] Cleanup trap: `trap 'rm -f "$temp_file"' EXIT`

---

## 🎯 Final Validation

- [ ] Run `bash -n script.sh` (syntax check)
- [ ] Test the actual change works
- [ ] If logging: verify log file is created and contains output
- [ ] Run twice to ensure idempotency

---

## 📌 Quick Reference

### Minimal Logging Template

```bash
# At script start
LOG_FILE="$HOME/bootstrap-tools-install-$(date +%Y%m%d_%H%M%S).log"
echo "Script started at $(date)" > "$LOG_FILE"

# Logging function
log_info() {
    echo "[INFO] $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "$LOG_FILE"
}

# At script end
echo "Log saved to: $LOG_FILE"
```

### Non-Interactive Mode Template

```bash
INTERACTIVE=true
if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
    INTERACTIVE=false
fi
```

---

## 👨‍💼 Senior Developer/Reviewer Section

**Reviewer Name:** `Your Name`  
**Review Date:** `YYYY-MM-DD`

### 1. Checklist Review

- [ ] Reviewed developer's modification summary
- [ ] Understand what was changed and why
- [ ] Developer's self-validation results noted

### 2. Compliance Check

- [ ] Compared changes against full CODING_STANDARDS.md
- [ ] Error handling properly implemented
- [ ] Logging comprehensive and follows standards
- [ ] Security practices followed (permissions, validation)
- [ ] Documentation clear and complete

### 3. Functional Testing

- [ ] Script runs successfully with the changes
- [ ] Primary functionality works as intended
- [ ] Error conditions handled gracefully

### 4. Non-Interactive Mode Testing

- [ ] Tested with `NON_INTERACTIVE=1` or relevant env vars
- [ ] No prompts shown in non-interactive mode
- [ ] Script completes successfully without user input

### 5. Remote Execution Testing

- [ ] Tested via pipe: `cat script.sh | bash`
- [ ] No relative path issues
- [ ] Environment variables work correctly

### 6. Idempotency Verification

- [ ] Ran script multiple times consecutively
- [ ] No errors on subsequent runs
- [ ] No duplicate configurations or side effects

### 7. Review Feedback

**Overall Assessment:** [ ] APPROVED / [ ] NEEDS CHANGES

**Strengths:**
<!-- What was done well -->

**Issues Found:**
<!-- Any problems that need fixing -->

**Recommendations:**
<!-- Suggestions for improvement -->

---

**Remember:** This checklist is about catching the important stuff, not perfection. Focus on what matters for your specific change.
