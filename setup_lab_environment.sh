#!/bin/bash
# =============================================================================
# LFS458 Lab Environment Setup Script
# Run this on EACH NODE before class (controller, worker1, worker2)
# Ubuntu 22.04 | kubeadm 1.36.1 | containerd | Calico CNI
# Usage: sudo bash setup_lab_environment.sh [username]
# =============================================================================

set -e

LAB_USER="${1:-guru}"
LAB_HOME="/home/${LAB_USER}/lfs458"
REPO_URL="https://github.com/helmsman-k8s/lfs458-labs.git"
REPO_BRANCH="rebuild-2025"
REPO_CLONE_DIR="/tmp/lfs458-repo-setup"

echo "=============================================="
echo " LFS458 Lab Environment Setup"
echo " Target user : $LAB_USER"
echo " Lab root    : $LAB_HOME"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Ensure user exists
# -----------------------------------------------------------------------------
if ! id "$LAB_USER" &>/dev/null; then
    echo "[0] Creating user $LAB_USER..."
    useradd -m -s /bin/bash "$LAB_USER"
    echo "${LAB_USER}:work" | chpasswd
    usermod -aG sudo "$LAB_USER"
    echo "    User $LAB_USER created (password: work)"
fi

# -----------------------------------------------------------------------------
# Install git if missing
# -----------------------------------------------------------------------------
echo "[1/3] Checking for git..."
if ! command -v git &>/dev/null; then
    echo "    Installing git..."
    apt-get install -y git -qq
fi
echo "    git OK"

# -----------------------------------------------------------------------------
# Clone repo and copy lab files
# -----------------------------------------------------------------------------
echo "[2/3] Fetching lab files from GitHub (branch: $REPO_BRANCH)..."
rm -rf "$REPO_CLONE_DIR"
git clone --depth=1 -b "$REPO_BRANCH" "$REPO_URL" "$REPO_CLONE_DIR"

mkdir -p "$LAB_HOME"
cp -r "$REPO_CLONE_DIR/lfs458/." "$LAB_HOME/"
rm -rf "$REPO_CLONE_DIR"
echo "    Lab files staged to $LAB_HOME"

# -----------------------------------------------------------------------------
# Fix permissions
# -----------------------------------------------------------------------------
echo "[3/3] Setting permissions..."
chown -R "${LAB_USER}:${LAB_USER}" "$LAB_HOME"
find "$LAB_HOME" -type f | xargs chmod 644 2>/dev/null || true
find "$LAB_HOME" -type d | xargs chmod 755

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo " Setup complete!"
echo "=============================================="
echo ""
echo " Lab root   : $LAB_HOME"
echo " Folders    : $(find $LAB_HOME -mindepth 1 -maxdepth 1 -type d | wc -l)"
echo " YAML files : $(find $LAB_HOME -name '*.yaml' | wc -l)"
echo " JSON files : $(find $LAB_HOME -name '*.json' | wc -l)"
echo ""
echo " Verify with:"
echo "   ls -la $LAB_HOME"
echo "   find $LAB_HOME -name '*.yaml' | sort"
