#!/bin/bash

# Run shellcheck on all shell scripts in the repository
# This script validates all shell scripts and provides a summary

set -euo pipefail

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    BOLD='\033[1m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    NC=''
    BOLD=''
fi

echo -e "${CYAN}${BOLD}ShellCheck Validation Report${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo -e "${RED}Error: shellcheck is not installed${NC}"
    echo "Install it with: sudo apt-get install shellcheck"
    echo "Or run: ./bootstrap/bootstrap.sh"
    exit 1
fi

echo -e "ShellCheck version: $(shellcheck --version | grep version: | awk '{print $2}')"
echo ""

# Find all shell scripts
scripts=$(find . -name "*.sh" -type f -not -path "./.git/*" | sort)
total_scripts=$(echo "$scripts" | wc -l)

echo -e "Found ${BOLD}$total_scripts${NC} shell scripts"
echo ""

passed_count=0
failed_count=0
failed_scripts=""

# Run shellcheck on each script
for script in $scripts; do
    echo -n "Checking $script... "
    
    # Run shellcheck with error severity (matching CI)
    if shellcheck -S error "$script" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((passed_count++))
    else
        echo -e "${RED}✗${NC}"
        ((failed_count++))
        failed_scripts="$failed_scripts$script\n"
        
        # Show the errors
        echo -e "${YELLOW}  Issues found:${NC}"
        shellcheck -S error "$script" 2>&1 | sed 's/^/    /'
        echo ""
    fi
done

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}Summary:${NC}"
echo -e "  Total scripts: $total_scripts"
echo -e "  ${GREEN}Passed: $passed_count${NC}"
echo -e "  ${RED}Failed: $failed_count${NC}"

if [[ $failed_count -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}${BOLD}✓ All scripts passed ShellCheck validation!${NC}"
else
    echo ""
    echo -e "${RED}${BOLD}✗ Some scripts failed validation${NC}"
    echo ""
    echo -e "${RED}Failed scripts:${NC}"
    echo -e "$failed_scripts"
    echo "Please fix the issues before committing."
fi

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

# Exit with non-zero if any scripts failed
exit $failed_count