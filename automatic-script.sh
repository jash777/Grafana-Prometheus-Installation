#!/bin/bash

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
    local step=0.01
    local progress=0
    local bar_length=40

    while [ $progress -lt 100 ]; do
        local filled=$(printf "%-${progress}s" "=")
        local empty=$(printf "%-$((bar_length - progress))s" " ")
        printf "\r[${filled// /=}${empty}] ${progress}%%"
        progress=$((progress + 1))
        sleep $step
    done
    echo
}

# Welcome message
clear
print_centered "Welcome to the Grafana and Prometheus Installer" "BLUE"
print_centered "for Ubuntu 20.04 and 22.04" "BLUE"
echo

# Function to handle errors
handle_error() {
    print_color "RED" "Error occurred in line $1: $2"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Function to check if a command was successful
check_success() {
    if [ $? -ne 0 ]; then
        handle_error $LINENO "Failed to $1"
    fi
}

# Function to install a package
install_package() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        print_color "YELLOW" "Installing $1..."
        sudo apt-get install -y "$1" > /dev/null 2>&1
        check_success "install $1"
        print_color "GREEN" "$1 installed successfully."
    else
        print_color "GREEN" "$1 is already installed."
    fi
}

# Function to create a user if it doesn't exist
create_user_if_not_exists() {
    local base_username="$1"
    local username="$base_username"
    local i=1

    while id "$username" &>/dev/null; do
        username="${base_username}${i}"
        ((i++))
    done

    sudo useradd --no-create-home --shell /bin/false "$username" >/dev/null 2>&1
    check_success "create user $username"
    echo "$username"
}

# Function to check if a service is already installed and running
check_service() {
    if systemctl is-active --quiet $1; then
        print_color "YELLOW" "$1 is already installed and running."
        read -p "Do you want to reinstall $1? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_color "YELLOW" "Stopping $1 service..."
            sudo systemctl stop $1
            check_success "stop $1 service"
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# Function to get Ubuntu version
get_ubuntu_version() {
    lsb_release -rs
}

# Function to compare versions
version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

# Check Ubuntu version
UBUNTU_VERSION=$(get_ubuntu_version)
if version_gt $UBUNTU_VERSION "22.04"; then
    print_color "YELLOW" "This script is tested on Ubuntu 20.04 and 22.04. Your version is $UBUNTU_VERSION. Proceed with caution."
elif version_gt "20.04" $UBUNTU_VERSION; then
    print_color "RED" "This script requires Ubuntu 20.04 or later. Your version is $UBUNTU_VERSION. Exiting."
    exit 1
fi

# Update package list
print_color "BLUE" "Updating package list..."
sudo apt-get update > /dev/null 2>&1
check_success "update package list"
print_color "GREEN" "Package list updated successfully."

# Install required packages
install_package "apt-transport-https"
install_package "software-properties-common"
install_package "wget"
install_package "gnupg"

# Install Grafana
if check_service grafana-server; then
    print_color "BLUE" "Installing Grafana..."
    if ! wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add - > /dev/null 2>&1; then
        handle_error $LINENO "Failed to add Grafana GPG key"
    fi

    echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list > /dev/null 2>&1
    check_success "add Grafana repository"

    sudo apt-get update > /dev/null 2>&1
    check_success "update package list after adding Grafana repository"

    install_package "grafana"

    # Start and enable Grafana service
    print_color "YELLOW" "Starting Grafana service..."
    sudo systemctl start grafana-server
    check_success "start Grafana service"

    sudo systemctl enable grafana-server > /dev/null 2>&1
    check_success "enable Grafana service"
    print_color "GREEN" "Grafana installed and started successfully."
else
    print_color "YELLOW" "Skipping Grafana installation as it's already installed and you chose not to reinstall."
fi

# Install Prometheus
if check_service prometheus; then
    print_color "BLUE" "Installing Prometheus..."
    PROMETHEUS_VERSION="2.37.0"
    if [ ! -f "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz > /dev/null 2>&1
        check_success "download Prometheus"
    fi

    tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz > /dev/null 2>&1
    check_success "extract Prometheus archive"

    if [ -d "/opt/prometheus" ]; then
        sudo mv /opt/prometheus /opt/prometheus_old_$(date +%Y%m%d%H%M%S)
        check_success "backup existing Prometheus installation"
    fi

    sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 /opt/prometheus
    check_success "move Prometheus to /opt"

    # Create Prometheus user
    PROMETHEUS_USER=$(create_user_if_not_exists "prometheus")
    print_color "GREEN" "Using user: $PROMETHEUS_USER for Prometheus"

    sudo chown -R "$PROMETHEUS_USER:$PROMETHEUS_USER" /opt/prometheus
    check_success "set ownership for Prometheus directory"

    # Create Prometheus configuration directory if it doesn't exist
    sudo mkdir -p /etc/prometheus
    check_success "create Prometheus configuration directory"

    # Create Prometheus configuration
    cat << EOF | sudo tee /etc/prometheus/prometheus.yml > /dev/null 2>&1
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    check_success "create Prometheus configuration"

    # Create Prometheus systemd service
    cat << EOF | sudo tee /etc/systemd/system/prometheus.service > /dev/null 2>&1
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_USER}
Type=simple
ExecStart=/opt/prometheus/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/opt/prometheus/consoles \
    --web.console.libraries=/opt/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF
    check_success "create Prometheus systemd service"

    # Create Prometheus data directory
    sudo mkdir -p /var/lib/prometheus
    sudo chown "$PROMETHEUS_USER:$PROMETHEUS_USER" /var/lib/prometheus
    check_success "create and set permissions for Prometheus data directory"

    # Reload systemd, start and enable Prometheus
    sudo systemctl daemon-reload
    check_success "reload systemd"

    print_color "YELLOW" "Starting Prometheus service..."
    sudo systemctl start prometheus
    check_success "start Prometheus service"

    sudo systemctl enable prometheus > /dev/null 2>&1
    check_success "enable Prometheus service"
    print_color "GREEN" "Prometheus installed and started successfully."
else
    print_color "YELLOW" "Skipping Prometheus installation as it's already installed and you chose not to reinstall."
fi

# Configure Grafana to use Prometheus as a data source
print_color "BLUE" "Configuring Grafana data source..."
sudo mkdir -p /etc/grafana/provisioning/datasources
check_success "create Grafana datasources directory"

cat << EOF | sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null 2>&1
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF
check_success "configure Grafana data source"

# Restart Grafana to apply changes
print_color "YELLOW" "Restarting Grafana service..."
sudo systemctl restart grafana-server
check_success "restart Grafana service"

print_color "BLUE" "Installation and configuration in progress..."
show_progress 100

print_color "GREEN" "Installation and configuration completed successfully!"
print_color "BLUE" "Grafana is accessible at http://localhost:3000 (default credentials: admin/admin)"
print_color "BLUE" "Prometheus is accessible at http://localhost:9090"
