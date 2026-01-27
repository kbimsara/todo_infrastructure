# infrastructure.tf
# Complete GCP Infrastructure in a Single File
# VM + Load Balancer + Docker Containers (Next.js + MongoDB)

# ============================================
# CONFIGURATION
# ============================================
# Edit these variables before running terraform apply

variable "project_id" {
  description = "Your GCP Project ID"
  type        = string
  default     = "vast-operator-450405-g4"  # ← CHANGE THIS
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "vm_name" {
  type    = string
  default = "todo-app-vm"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"  # 2 vCPU, 4GB RAM (sufficient for Next.js + MongoDB)
}

variable "disk_size_gb" {
  type    = number
  default = 30  # Increased for app + MongoDB data
}

variable "github_repo" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/kbimsara/todo_infrastructure.git"  # ← CHANGE THIS
}

# ============================================
# TERRAFORM & PROVIDER SETUP
# ============================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================
# ENABLE APIS
# ============================================

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# ============================================
# FIREWALL RULES
# ============================================

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
  
  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "allow_https" {
  name    = "allow-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["https-server"]
  
  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "allow-health-check"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["http-server"]
  
  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-todo"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
  
  depends_on = [google_project_service.compute]
}

# ============================================
# COMPUTE ENGINE VM
# ============================================

resource "google_compute_instance" "nextjs_vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    
    # Log all output
    exec > >(tee -a /var/log/startup-script.log)
    exec 2>&1
    
    echo "Starting Todo App deployment..."
    
    # Update system
    apt-get update
    apt-get upgrade -y
    
    # Install required packages
    apt-get install -y \
      docker.io \
      git \
      curl \
      ca-certificates
    
    systemctl start docker
    systemctl enable docker
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Add user to docker group
    usermod -aG docker ubuntu || true
    
    # Clone repository
    cd /home/ubuntu
    if [ ! -d "todo_infrastructure" ]; then
      git clone ${var.github_repo} todo_infrastructure || {
        echo "Failed to clone repository. Creating manual setup..."
        mkdir -p todo_infrastructure/Deployee
      }
    fi
    
    # Create docker-compose.yml for Todo App
    mkdir -p /home/ubuntu/todo_infrastructure/Deployee
    cat > /home/ubuntu/todo_infrastructure/Deployee/docker-compose.yml <<'COMPOSE_EOF'
version: '3.8'

services:
  mongodb:
    image: mongo:7.0
    container_name: todo-mongodb
    restart: unless-stopped
    environment:
      MONGO_INITDB_DATABASE: todoapp
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
      - mongodb_config:/data/configdb
    networks:
      - todo-network
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh localhost:27017/todoapp --quiet
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    image: ghcr.io/your-username/todo-app:latest
    container_name: todo-app
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - MONGODB_URI=mongodb://mongodb:27017/todoapp
      - NODE_ENV=production
    depends_on:
      mongodb:
        condition: service_healthy
    networks:
      - todo-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  mongodb_data:
    driver: local
  mongodb_config:
    driver: local

networks:
  todo-network:
    driver: bridge
COMPOSE_EOF
    
    # Set ownership
    chown -R ubuntu:ubuntu /home/ubuntu/todo_infrastructure
    
    # Start containers
    cd /home/ubuntu/todo_infrastructure/Deployee
    docker-compose pull || true
    docker-compose up -d
    
    echo "Todo App deployment completed!"
    echo "Access the app at: http://$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google'):3000"
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
  
  depends_on = [
    google_project_service.compute,
    google_compute_firewall.allow_http,
    google_compute_firewall.allow_https,
    google_compute_firewall.allow_health_check
  ]
}

# ============================================
# HEALTH CHECK
# ============================================

resource "google_compute_health_check" "nextjs_health_check" {
  name               = "todo-app-health-check"
  check_interval_sec = 10
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 3000
    request_path = "/"
  }
  
  depends_on = [google_project_service.compute]
}

# ============================================
# INSTANCE GROUP
# ============================================

resource "google_compute_instance_group" "nextjs_ig" {
  name = "todo-app-instance-group"
  zone = var.zone

  instances = [
    google_compute_instance.nextjs_vm.id
  ]

  named_port {
    name = "http"
    port = 3000
  }
}

# ============================================
# LOAD BALANCER
# ============================================

resource "google_compute_backend_service" "nextjs_backend" {
  name                  = "todo-app-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  enable_cdn            = false
  health_checks         = [google_compute_health_check.nextjs_health_check.id]

  backend {
    group           = google_compute_instance_group.nextjs_ig.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "nextjs_lb" {
  name            = "todo-app-load-balancer"
  default_service = google_compute_backend_service.nextjs_backend.id
}

resource "google_compute_target_http_proxy" "nextjs_http_proxy" {
  name    = "todo-app-http-proxy"
  url_map = google_compute_url_map.nextjs_lb.id
}

resource "google_compute_global_address" "nextjs_ip" {
  name = "todo-app-static-ip"
}

resource "google_compute_global_forwarding_rule" "nextjs_http_rule" {
  name                  = "todo-app-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.nextjs_http_proxy.id
  ip_address            = google_compute_global_address.nextjs_ip.id
}

# ============================================
# OUTPUTS
# ============================================

output "vm_name" {
  description = "Name of the VM instance"
  value       = google_compute_instance.nextjs_vm.name
}

output "vm_external_ip" {
  description = "External IP of the VM"
  value       = google_compute_instance.nextjs_vm.network_interface[0].access_config[0].nat_ip
}

output "load_balancer_ip" {
  description = "Load Balancer IP address"
  value       = google_compute_global_address.nextjs_ip.address
}

output "application_url" {
  description = "URL to access your application"
  value       = "http://${google_compute_global_address.nextjs_ip.address}"
}

output "direct_vm_url" {
  description = "Direct VM access (bypass load balancer)"
  value       = "http://${google_compute_instance.nextjs_vm.network_interface[0].access_config[0].nat_ip}:3000"
}

output "ssh_command" {
  description = "Command to SSH into the VM"
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id}"
}

output "docker_logs_command" {
  description = "Command to view Docker logs"
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id} --command='cd /home/ubuntu/todo_infrastructure/Deployee && sudo docker-compose logs -f'"
}

# ============================================
# USAGE INSTRUCTIONS
# ============================================
# 
# 1. Install Terraform: https://www.terraform.io/downloads
# 
# 2. Install gcloud CLI and authenticate:
#    gcloud auth login
#    gcloud auth application-default login
# 
# 3. Edit this file and change:
#    - project_id (line 12)
#    - mongodb_password (line 36)
# 
# 4. Initialize Terraform:
#    terraform init
# 
# 5. Preview changes:
#    terraform plan
# 
# 6. Deploy infrastructure:
#    terraform apply
# 
# 7. Get outputs:
#    terraform output
# 
# 8. Access your app:
#    terraform output -raw application_url
# 
# 9. SSH to VM:
#    terraform output -raw ssh_command | bash
# 
# 10. Destroy when done:
#     terraform destroy
# 
# ============================================
