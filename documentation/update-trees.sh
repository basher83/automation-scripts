#!/bin/bash

# Manual script to update tree structures in documentation files
# Usage: ./scripts/update-trees.sh

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🌳 Updating documentation trees...${NC}"

# Check if tree command is available
if ! command -v tree &> /dev/null; then
    echo -e "${RED}Error: 'tree' command not found. Please install it:${NC}"
    echo "  Ubuntu/Debian: sudo apt-get install tree"
    echo "  MacOS: brew install tree"
    exit 1
fi

# Function to update tree in a file between markers
update_tree_in_file() {
    local file=$1
    local directory=$2
    local tree_flags="${3:--a -I '.git|node_modules|.DS_Store' --charset ascii}"
    
    if [[ ! -f "$file" ]]; then
        echo -e "${YELLOW}Warning: File $file not found, skipping...${NC}"
        return
    fi
    
    # Check if file has tree markers
    if ! grep -q "<!-- TREE-START -->" "$file" || ! grep -q "<!-- TREE-END -->" "$file"; then
        echo -e "${YELLOW}Warning: Tree markers not found in $file, skipping...${NC}"
        return
    fi
    
    echo -e "📄 Updating tree in: $file"
    
    # Generate tree
    local tree_output=$(tree $directory $tree_flags)
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Process file line by line
    local in_tree_section=false
    local tree_written=false
    
    while IFS= read -r line; do
        if [[ "$line" == *"<!-- TREE-START -->"* ]]; then
            echo "$line" >> "$temp_file"
            echo '```plaintext' >> "$temp_file"
            echo "$tree_output" >> "$temp_file"
            echo '```' >> "$temp_file"
            in_tree_section=true
            tree_written=true
        elif [[ "$line" == *"<!-- TREE-END -->"* ]]; then
            echo "$line" >> "$temp_file"
            in_tree_section=false
        elif [[ "$in_tree_section" == false ]]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$file"
    
    # Replace original file
    mv "$temp_file" "$file"
    
    echo -e "${GREEN}✓ Updated tree in $file${NC}"
}

# Update trees in various documentation files
echo -e "\n${GREEN}Updating documentation trees...${NC}\n"

# Update core-github-repos.md - main tree
update_tree_in_file "mission-control/core-github-repos.md" "." "-L 2 -d -I '.git|node_modules|.DS_Store|.github|.cursor' --charset ascii"

# Update core-github-repos.md - docs tree (if using DOCS-TREE markers)
# First check if DOCS-TREE markers exist in the file
if grep -q "<!-- DOCS-TREE-START -->" "mission-control/core-github-repos.md"; then
    # Create a temporary file with modified markers
    sed 's/<!-- DOCS-TREE-START -->/<!-- TREE-START -->/g; s/<!-- DOCS-TREE-END -->/<!-- TREE-END -->/g' \
        "mission-control/core-github-repos.md" > "/tmp/temp-core-github-repos.md"
    
    # Update the docs tree
    update_tree_in_file "/tmp/temp-core-github-repos.md" "." "-I '.git|node_modules|.DS_Store|.github|.cursor' --charset ascii"
    
    # Change markers back
    sed 's/<!-- TREE-START -->/<!-- DOCS-TREE-START -->/g; s/<!-- TREE-END -->/<!-- DOCS-TREE-END -->/g' \
        "/tmp/temp-core-github-repos.md" > "mission-control/core-github-repos.md"
    
    rm "/tmp/temp-core-github-repos.md"
fi

# Update README.md if it has tree markers
update_tree_in_file "README.md" "." "-L 3 -d -I '.git|node_modules|.DS_Store|.github|.cursor' --charset ascii"

# Add more files as needed
# update_tree_in_file "path/to/file.md" "directory/to/scan" "optional-tree-flags"

echo -e "\n${GREEN}🎉 Tree update complete!${NC}"
echo -e "${YELLOW}Note: Don't forget to commit the changes if they look good.${NC}"