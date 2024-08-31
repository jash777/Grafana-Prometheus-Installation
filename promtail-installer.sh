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
    apt-get update && apt-get install -y curl gpg apt-transport-https
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

# Function to install Promtail
install_promtail() {
    print_progress "Installing Promtail..."
    apt-get install -y promtail
    if [[ $? -ne 0 ]]; then
        print_error "Failed to install Promtail"
    fi
    print_success "Promtail installed successfully"
}

# Function to configure Promtail
configure_promtail() {
    print_progress "Configuring Promtail..."
    read -p "Enter Loki IP address: " loki_ip
    cat << EOF > /etc/promtail/config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://192.168.1.20:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
    - targets:
        - localhost
      labels:
        job: varlogs
        __path__: /var/log/*log

  - job_name: syslog
    syslog:
      listen_address: 0.0.0.0:1514
      idle_timeout: 60s
      label_structured_data: yes
      labels:
        job: "syslog"
    relabel_configs:
      - source_labels: ['__syslog_connection_ip_address']
        target_label: 'ip_address'
      - source_labels: ['__syslog_message_severity']
        target_label: 'severity'
      - source_labels: ['__syslog_message_facility']
        target_label: 'facility'
      - source_labels: ['__syslog_message_hostname']
        target_label: 'host'

  - job_name: ssh
    static_configs:
    - targets:
        - 0.0.0.0
      labels:
        job: ssh
        __path__: /var/log/auth.log
EOF
    print_success "Promtail configured successfully"
}

# Function to start Promtail service
start_promtail() {
    print_progress "Starting Promtail service..."
    systemctl start promtail
    systemctl enable promtail
    if [[ $? -ne 0 ]]; then
        print_error "Failed to start Promtail service"
    fi
    print_success "Promtail service started successfully"
}

# Function to add firewall rule
add_firewall_rule() {
    print_progress "Adding firewall rule for Promtail..."
    if command -v ufw > /dev/null; then
        ufw allow 9080/tcp
        ufw reload
        print_success "Firewall rule added successfully (UFW)"
    elif command -v iptables > /dev/null; then
        iptables -A INPUT -p tcp --dport 9080 -j ACCEPT
        iptables-save > /etc/iptables/rules.v4
        print_success "Firewall rule added successfully (iptables)"
    else
        print_error "No supported firewall (UFW or iptables) found"
    fi
}

# Function to show Promtail status
show_promtail_status() {
    print_progress "Checking Promtail status..."
    systemctl status promtail
}

# Main function
main() {
    print_color $BLUE "
    ╔═══════════════════════════════════════════╗
    ║     Promtail Installer for Ubuntu         ║
    ╚═══════════════════════════════════════════╝"

    check_root

    ubuntu_version=$(get_ubuntu_version)
    print_progress "Detected Ubuntu version: $ubuntu_version"

    install_prerequisites
    add_grafana_repo
    install_promtail
    configure_promtail
    start_promtail
    add_firewall_rule
    show_promtail_status

    print_color $GREEN "
    ╔═══════════════════════════════════════════╗
    ║     Promtail Installation Complete!       ║
    ╚═══════════════════════════════════════════╝"
}

# Run the main function
main
