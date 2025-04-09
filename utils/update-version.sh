#!/bin/bash

# Script to update version, commit changes, and push to GitHub
# Usage: ./utils/update-version.sh [major|minor|patch] [commit message]

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
VERSION_FILE="VERSION"
VERSION_TYPE=${1:-"patch"}
COMMIT_MESSAGE=${2:-"Bump version"}

# Check if VERSION file exists
if [ ! -f "$VERSION_FILE" ]; then
    echo_error "VERSION file not found. Please create it first."
    exit 1
fi

# Read current version
CURRENT_VERSION=$(cat "$VERSION_FILE")
echo_info "Current version: $CURRENT_VERSION"

# Split version into components
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]}
PATCH=${VERSION_PARTS[2]}

# Update version based on type
case "$VERSION_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo_error "Invalid version type. Use 'major', 'minor', or 'patch'."
        exit 1
        ;;
esac

# Create new version
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo_info "New version: $NEW_VERSION"

# Update VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"
echo_success "Updated VERSION file to $NEW_VERSION"

# Check if git is available
if ! command -v git &> /dev/null; then
    echo_warning "Git not found. VERSION file updated, but changes not committed."
    exit 0
fi

# Check if current directory is a git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo_warning "Not a git repository. VERSION file updated, but changes not committed."
    exit 0
fi

# Commit and push changes
echo_info "Committing changes..."
git add "$VERSION_FILE"
git commit -m "$COMMIT_MESSAGE: $NEW_VERSION"

echo_info "Pushing changes to GitHub..."
git push

echo_success "Version updated and changes pushed to GitHub."
echo_info "GitHub Actions will automatically create a release with tag v$NEW_VERSION"