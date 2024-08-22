#!/bin/bash

set -e

# Function to handle errors
handle_error() {
    echo "Error occurred in line $1: $2"
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
        echo "Installing $1..."
        sudo apt-get install -y "$1"
        check_success "install $1"
    else
        echo "$1 is already installed"
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
        echo "$1 is already installed and running."
        read -p "Do you want to reinstall $1? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Stopping $1 service..."
            sudo systemctl stop $1
            check_success "stop $1 service"
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# Update package list
echo "Updating package list..."
sudo apt-get update
check_success "update package list"

# Install required packages
install_package "apt-transport-https"
install_package "software-properties-common"
install_package "wget"

# Install Grafana
if check_service grafana-server; then
    echo "Installing Grafana..."
    if ! wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -; then
        handle_error $LINENO "Failed to add Grafana GPG key"
    fi

    echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
    check_success "add Grafana repository"

    sudo apt-get update
    check_success "update package list after adding Grafana repository"

    install_package "grafana"

    # Start and enable Grafana service
    echo "Starting Grafana service..."
    sudo systemctl start grafana-server
    check_success "start Grafana service"

    sudo systemctl enable grafana-server
    check_success "enable Grafana service"
else
    echo "Skipping Grafana installation as it's already installed and you chose not to reinstall."
fi

# Install Prometheus
if check_service prometheus; then
    echo "Installing Prometheus..."
    PROMETHEUS_VERSION="2.37.0"
    if [ ! -f "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
        check_success "download Prometheus"
    fi

    tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    check_success "extract Prometheus archive"

    if [ -d "/opt/prometheus" ]; then
        sudo mv /opt/prometheus /opt/prometheus_old_$(date +%Y%m%d%H%M%S)
        check_success "backup existing Prometheus installation"
    fi

    sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 /opt/prometheus
    check_success "move Prometheus to /opt"

    # Create Prometheus user
    PROMETHEUS_USER=$(create_user_if_not_exists "prometheus")
    echo "Using user: $PROMETHEUS_USER for Prometheus"

    sudo chown -R "$PROMETHEUS_USER:$PROMETHEUS_USER" /opt/prometheus
    check_success "set ownership for Prometheus directory"

    # Create Prometheus configuration directory if it doesn't exist
    sudo mkdir -p /etc/prometheus
    check_success "create Prometheus configuration directory"

    # Create Prometheus configuration
    cat << EOF | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    check_success "create Prometheus configuration"

    # Create Prometheus systemd service
    cat << EOF | sudo tee /etc/systemd/system/prometheus.service
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

    echo "Starting Prometheus service..."
    sudo systemctl start prometheus
    check_success "start Prometheus service"

    sudo systemctl enable prometheus
    check_success "enable Prometheus service"
else
    echo "Skipping Prometheus installation as it's already installed and you chose not to reinstall."
fi

# Configure Grafana to use Prometheus as a data source
echo "Configuring Grafana data source..."
sudo mkdir -p /etc/grafana/provisioning/datasources
check_success "create Grafana datasources directory"

cat << EOF | sudo tee /etc/grafana/provisioning/datasources/prometheus.yml
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
echo "Restarting Grafana service..."
sudo systemctl restart grafana-server
check_success "restart Grafana service"

echo "Installation and configuration completed successfully!"
echo "Grafana is accessible at http://localhost:3000 (default credentials: admin/admin)"
echo "Prometheus is accessible at http://localhost:9090"
