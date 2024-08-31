#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

# Function to print progress
print_progress() {
    printf "${YELLOW}[*] %s${NC}\n" "$1"
}

# Function to print success
print_success() {
    printf "${GREEN}[+] %s${NC}\n" "$1"
}

# Function to print error and exit
print_error() {
    printf "${RED}[-] Error: %s${NC}\n" "$1"
    exit 1
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
    fi
}

# Function to get Ubuntu version
get_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$VERSION_ID"
    else
        print_error "Cannot determine Ubuntu version"
    fi
}

# Function to install prerequisites
install_prerequisites() {
    print_progress "Installing prerequisites..."
    apt-get update && apt-get install -y curl gpg apt-transport-https software-properties-common
    if [[ $? -ne 0 ]]; then
        print_error "Failed to install prerequisites"
    fi
    print_success "Prerequisites installed successfully"
}

# Function to add Grafana repository
add_grafana_repo() {
    print_progress "Adding Grafana repository..."
    curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana.gpg
    echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
    apt-get update
    if [[ $? -ne 0 ]]; then
        print_error "Failed to add Grafana repository"
    fi
    print_success "Grafana repository added successfully"
}

# Function to install Loki
install_loki() {
    print_progress "Installing Loki..."
    apt-get install -y loki
    if [[ $? -ne 0 ]]; then
        print_error "Failed to install Loki"
    fi
    print_success "Loki installed successfully"
}

# Function to configure Loki
configure_loki() {
    print_progress "Configuring Loki..."
    mkdir -p /etc/loki
    cat << EOF > /etc/loki/loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-05-15
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /tmp/loki/index

  filesystem:
    directory: /tmp/loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOF

    # Create Loki systemd service
    cat << EOF > /etc/systemd/system/loki.service
[Unit]
Description=Loki service
After=network.target

[Service]
Type=simple
User=loki
ExecStart=/usr/bin/loki -config.file /etc/loki/loki-config.yaml

[Install]
WantedBy=multi-user.target
EOF

    # Create loki user
    useradd --system loki

    # Set correct permissions
    chown -R loki:loki /etc/loki /tmp/loki

    print_success "Loki configured successfully"
}

# Function to start Loki service
start_loki() {
    print_progress "Starting Loki service..."
    systemctl daemon-reload
    systemctl start loki
    systemctl enable loki
    if [[ $? -ne 0 ]]; then
        print_error "Failed to start Loki service"
    fi
    print_success "Loki service started successfully"
}

# Function to add firewall rule
add_firewall_rule() {
    print_progress "Adding firewall rule for Loki..."
    if command -v ufw; then
        ufw allow 3100/tcp
        ufw reload
        print_success "Firewall rule added successfully (UFW)"
    else
        print_error "No supported firewall (UFW or iptables) found"
    fi
}

# Function to show Loki status
show_loki_status() {
    print_progress "Checking Loki status..."
    systemctl status loki
}

# Function to generate and display bearer token
generate_bearer_token() {
    print_progress "Generating bearer token..."
    bearer_token=$(openssl rand -hex 16)
    print_success "Bearer token generated: $bearer_token"
    print_color $YELLOW "Please update your Promtail configuration with this bearer token."
}

# Main function
main() {
    print_color $BLUE "
    ╔═══════════════════════════════════════════╗
    ║       Loki Installer for Ubuntu           ║
    ╚═══════════════════════════════════════════╝"

    check_root

    ubuntu_version=$(get_ubuntu_version)
    print_progress "Detected Ubuntu version: $ubuntu_version"

    install_prerequisites
    add_grafana_repo
    install_loki
    configure_loki
    start_loki
    add_firewall_rule
    show_loki_status
    generate_bearer_token

    print_color $GREEN "
    ╔═══════════════════════════════════════════╗
    ║       Loki Installation Complete!         ║
    ╚═══════════════════════════════════════════╝"
}

# Run the main function
main
