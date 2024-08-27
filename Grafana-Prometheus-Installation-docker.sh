#!/bin/bash

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly GRAFANA_VERSION="latest"
readonly PROMETHEUS_VERSION="latest"
readonly INSTALL_DIR="$HOME/docker-monitoring"
readonly GRAFANA_PORT=3000
readonly PROMETHEUS_PORT=9090

# Functions
log() {
    local level=$1
    shift
    printf "${!level}[${level}] %s${NC}\n" "$*" >&2
}

error() { log RED "$@"; }
warn() { log YELLOW "$@"; }
info() { log BLUE "$@"; }
success() { log GREEN "$@"; }

die() {
    error "$@"
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed. Aborting."
}

check_docker() {
    check_command docker
    if ! docker info >/dev/null 2>&1; then
        die "Docker daemon is not running. Please start Docker and try again."
    fi
    info "Docker is installed and running."
}

check_docker_compose() {
    if ! check_command docker-compose; then
        warn "Docker Compose is not installed. Attempting to install..."
        if ! sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
            die "Failed to download Docker Compose."
        fi
        sudo chmod +x /usr/local/bin/docker-compose
        success "Docker Compose installed successfully."
    else
        info "Docker Compose is already installed."
    fi
}

create_docker_compose_file() {
    cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
version: '3'
services:
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    ports:
      - "${GRAFANA_PORT}:3000"
    volumes:
      - grafana-storage:/var/lib/grafana
    depends_on:
      - prometheus

  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus

volumes:
  grafana-storage:
  prometheus-data:
EOF
    success "Docker Compose file created."
}

create_prometheus_config() {
    cat > "$INSTALL_DIR/prometheus.yml" <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    success "Prometheus configuration file created."
}

start_containers() {
    info "Starting containers..."
    if ! docker-compose -f "$INSTALL_DIR/docker-compose.yml" up -d; then
        die "Failed to start containers. Check the Docker Compose file and try again."
    fi
    success "Containers started successfully."
}

wait_for_grafana() {
    info "Waiting for Grafana to be ready..."
    local retries=30
    local wait_time=5
    while [ $retries -gt 0 ]; do
        if curl -s "http://localhost:${GRAFANA_PORT}/api/health" | grep -q "ok"; then
            success "Grafana is ready."
            return 0
        fi
        warn "Waiting for Grafana to be ready... (${retries} retries left)"
        sleep $wait_time
        retries=$((retries - 1))
    done
    die "Grafana did not become ready in time."
}

configure_grafana() {
    info "Configuring Grafana..."
    wait_for_grafana

    local datasource_payload='{
        "name":"Prometheus",
        "type":"prometheus",
        "url":"http://prometheus:9090",
        "access":"proxy",
        "isDefault":true
    }'

    if curl -s -X POST -H "Content-Type: application/json" \
        -d "$datasource_payload" \
        "http://admin:admin@localhost:${GRAFANA_PORT}/api/datasources" | grep -q "Datasource added"; then
        success "Prometheus datasource added to Grafana successfully."
    else
        warn "Failed to add Prometheus datasource to Grafana. You may need to configure it manually."
    fi
}

main() {
    info "Starting Grafana and Prometheus installation..."

    check_docker
    check_docker_compose

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || die "Failed to change to installation directory."

    create_docker_compose_file
    create_prometheus_config
    start_containers
    configure_grafana

    success "Installation completed successfully!"
    echo "Grafana is accessible at http://localhost:${GRAFANA_PORT} (default credentials: admin/admin)"
    echo "Prometheus is accessible at http://localhost:${PROMETHEUS_PORT}"
}

main "$@"
