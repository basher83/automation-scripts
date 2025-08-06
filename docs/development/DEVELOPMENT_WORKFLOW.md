# Development Workflow

This document outlines the standard workflow for modifying scripts in the automation-scripts repository.

## Overview

We use a two-tier development process that balances speed with compliance:

1. **Developers** use a streamlined checklist for quick self-validation
2. **Reviewers** perform thorough compliance checks against full standards

## 📝 Developer Workflow

### 1. Before You Start

- Identify what script you're modifying
- Gather official documentation for any tools you're adding
- Ensure you have Ubuntu/Debian installation instructions

### 2. Copy the Checklist

```bash
# From repository root
cp CODING_STANDARDS_CHECKLIST.md <target-dir>/checklist-$(date +%Y%m%d_%H%M%S).md

# Example for bootstrap modifications
cp CODING_STANDARDS_CHECKLIST.md bootstrap/checklist-$(date +%Y%m%d_%H%M%S).md
```

### 3. Fill Out the Modification Summary

Complete these sections at the top of your checklist:

- **Date**: Today's date
- **Developer**: Your name
- **Script**: Which script you're modifying
- **What**: Brief description of the change
- **Why**: Reason/ticket/request driving the change
- **Installation Instructions**: Official steps for Ubuntu/Debian
- **Official Docs**: Link to documentation

### 4. Complete the Checklist

Work through the checklist, checking only items relevant to your change:

- ✅ **Essential Checks**: Always required
- 📊 **Logging**: Required for installations/system changes
- 🔍 **Only If Applicable**: Skip sections that don't apply

### 5. Validate Your Changes

Run through the Final Validation section:

```bash
# Syntax check
bash -n your-script.sh

# Test functionality
./your-script.sh

# Verify logging (if applicable)
ls -la /var/log/your-script-*.log

# Test idempotency (run twice)
./your-script.sh
./your-script.sh
```

### 6. Submit Your Work

Include with your pull request:

- Your modified script
- The completed checklist
- Update to relevant documentation (README, etc.)
- Update to TOOLS.md (if adding new tools)

## 👨‍💼 Senior Developer/Reviewer Workflow

### 1. Review the Checklist

First, review the submitted checklist to understand:

- What was changed
- Why it was changed
- Developer's self-validation results

**Important**: Use the "Senior Developer/Reviewer Section" in the same checklist to track your review progress and provide feedback.

### 2. Line-by-Line Compliance Check

Compare the actual changes against [CODING_STANDARDS.md](../../CODING_STANDARDS.md):

#### Key Areas to Review:

- **Error Handling**: Proper use of `set -euo pipefail` and traps
- **Logging**: Comprehensive logging to `/var/log/` with timestamps
- **Idempotency**: Safe to run multiple times
- **Remote Execution**: Works via curl if applicable
- **Security**: No hardcoded secrets, proper permissions
- **Documentation**: Clear comments and user messages

### 3. Test the Changes

```bash
# Run the modified script
./modified-script.sh

# Check logs were created properly
tail -f /var/log/script-name-*.log

# Test non-interactive mode
NON_INTERACTIVE=1 ./modified-script.sh

# Test remote execution (if applicable)
cat modified-script.sh | bash
```

### 4. Provide Feedback

Complete the "Senior Developer/Reviewer Section" in the checklist with:

- **Overall Assessment**: Mark APPROVED or NEEDS CHANGES
- **Strengths**: Acknowledge what was done well
- **Issues Found**: Document any problems that need fixing
- **Recommendations**: Suggest improvements for future

For pull request comments:

- **Minor issues**: Comment on PR for developer to fix
- **Major issues**: Request changes with specific standards references
- **Good practices**: Acknowledge when standards are well-followed

## 📋 Example: Adding a New Tool

Here's a complete example of adding difftastic to bootstrap.sh:

### 1. Developer Creates Checklist

```bash
cp CODING_STANDARDS_CHECKLIST.md bootstrap/checklist-20250806_143022.md
```

### 2. Developer Fills Out Summary

```markdown
**Date:** 2025-08-06  
**Developer:** Jane Smith  
**Script:** bootstrap.sh  

### What am I modifying?
Adding difftastic (diff tool) to the bootstrap script

### Why am I modifying it?
Team request for better diff visualization in code reviews

### Installation Instructions
```bash
# For Ubuntu/Debian:
curl -fsSL https://github.com/Wilfred/difftastic/releases/latest/download/difft-x86_64-unknown-linux-gnu.tar.gz | tar -xz
sudo mv difft /usr/local/bin/
```

**Official Docs:** https://github.com/Wilfred/difftastic
```

### 3. Developer Implements

Following the patterns in bootstrap.sh:

```bash
# Install difftastic - semantic diff tool
log_step "Checking difftastic..."

if ! command -v difft &> /dev/null; then
    log_info "Installing difftastic..."
    # ... implementation following existing patterns
    log_info "✓ difftastic installed successfully!"
else
    log_info "difftastic is already installed"
fi
```

### 4. Developer Updates Documentation

- Adds difftastic to script summary output
- Updates bootstrap/README.md
- Adds entry to bootstrap/TOOLS.md

### 5. Reviewer Validates

- Checks logging is implemented
- Verifies idempotency
- Ensures non-interactive mode works
- Confirms follows existing patterns

## 🎯 Benefits of This Workflow

1. **Quick for developers**: 5-minute checklist vs 30-minute standards doc
2. **Thorough review**: Senior devs ensure full compliance
3. **Documentation trail**: Every change is documented with reasoning
4. **Learning tool**: Developers gradually learn standards through checklists
5. **Consistency**: All changes follow the same process

## 📚 Related Documents

- [CODING_STANDARDS.md](../../CODING_STANDARDS.md) - Full coding standards
- [CODING_STANDARDS_CHECKLIST.md](../../CODING_STANDARDS_CHECKLIST.md) - Developer checklist
- [TOOLS.md](../../bootstrap/TOOLS.md) - Tool tracking for bootstrap script

## 💡 Tips for Success

### For Developers:

- Keep the checklist with your code changes
- Don't skip the "Why" section - it helps reviewers
- Test in a clean environment when possible
- Ask if unsure about standards

### For Reviewers:

- Use the checklist to understand intent
- Reference specific standards when requesting changes
- Acknowledge good compliance practices
- Help developers learn through feedback

---

Remember: The goal is maintainable, reliable scripts. The workflow helps us achieve this efficiently.