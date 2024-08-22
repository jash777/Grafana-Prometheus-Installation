#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${!1}%s${NC}\n" "$2"
}

# Function to print centered text
print_centered() {
    local text="$1"
    local color="$2"
    local term_width=$(tput cols)
    local padding=$(( (term_width - ${#text}) / 2 ))
    printf "${!color}%*s%s%*s${NC}\n" $padding "" "$text" $padding ""
}

# Function to display progress bar
show_progress() {
    local duration=$1
    local step=0.1
    local progress=0
    local bar_length=40

    while [ $progress -lt 100 ]; do
        local filled=$(printf "%-${progress}s" "=")
        local empty=$(printf "%-$((bar_length - progress))s" " ")
        printf "\r[${filled// /=}${empty}] ${progress}%%"
        progress=$((progress + 2))
        sleep $step
    done
    echo
}

# Function to check if a command was successful
check_success() {
    if [ $? -ne 0 ]; then
        print_color "RED" "Error: $1"
        exit 1
    fi
}

# Function to check if Node Exporter is already installed
check_node_exporter() {
    if systemctl is-active --quiet node_exporter; then
        return 0
    else
        return 1
    fi
}

# Function to install Node Exporter
install_node_exporter() {
    # Define Node Exporter version and architecture
    NODE_EXPORTER_VERSION="1.6.1"
    ARCH="linux-amd64"

    # Create a temporary directory
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"

    print_color "YELLOW" "Downloading Node Exporter..."
    wget "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz" > /dev/null 2>&1
    check_success "Failed to download Node Exporter"

    print_color "YELLOW" "Extracting Node Exporter..."
    tar xvfz "node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz" > /dev/null 2>&1
    check_success "Failed to extract Node Exporter"

    print_color "YELLOW" "Moving Node Exporter binary to /usr/local/bin..."
    sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}/node_exporter" /usr/local/bin/
    check_success "Failed to move Node Exporter binary"

    print_color "YELLOW" "Creating Node Exporter user..."
    sudo useradd -rs /bin/false node_exporter
    check_success "Failed to create Node Exporter user"

    print_color "YELLOW" "Creating systemd service file..."
    cat << EOF | sudo tee /etc/systemd/system/node_exporter.service > /dev/null 2>&1
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    check_success "Failed to create systemd service file"

    print_color "YELLOW" "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    check_success "Failed to reload systemd daemon"

    print_color "YELLOW" "Starting Node Exporter..."
    sudo systemctl start node_exporter
    check_success "Failed to start Node Exporter"

    print_color "YELLOW" "Enabling Node Exporter to start on boot..."
    sudo systemctl enable node_exporter > /dev/null 2>&1
    check_success "Failed to enable Node Exporter"

    print_color "YELLOW" "Cleaning up..."
    cd
    rm -rf "$TMP_DIR"

    print_color "BLUE" "Installation in progress..."
    show_progress 100

    print_color "GREEN" "Node Exporter installation completed successfully!"
}

# Welcome message
clear
print_centered "Welcome to the Node Exporter Installer" "BLUE"
print_centered "for Ubuntu and other Linux distributions" "BLUE"
echo

# Check if Node Exporter is already installed
if check_node_exporter; then
    print_color "YELLOW" "Node Exporter is already installed and running."
    read -p "Do you want to reinstall? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_color "YELLOW" "Stopping Node Exporter service..."
        sudo systemctl stop node_exporter
        check_success "Failed to stop Node Exporter service"
        
        print_color "YELLOW" "Removing existing Node Exporter..."
        sudo rm -f /usr/local/bin/node_exporter
        sudo rm -f /etc/systemd/system/node_exporter.service
        sudo systemctl daemon-reload
        check_success "Failed to remove existing Node Exporter"
        
        install_node_exporter
    else
        print_color "GREEN" "Exiting without changes."
        exit 0
    fi
else
    install_node_exporter
fi

print_color "BLUE" "You can check its status using: sudo systemctl status node_exporter"
