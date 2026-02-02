# infrastructure.tf
# Complete GCP Infrastructure with Direct VM Access
# VM + Load Balancer + Docker Containers (Next.js + MongoDB)
# FIXED: Proper permissions and git configuration

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "my-app-todo-485623"
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
  default = "e2-medium"
}

variable "disk_size_gb" {
  type    = number
  default = 30
}

variable "github_repo" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/kbimsara/todo_infrastructure.git"
}

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

resource "google_compute_firewall" "allow_app_port" {
  name    = "allow-app-port-3000"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["3000"]
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
    access_config {}
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    
    # Log everything
    exec > >(tee -a /var/log/startup-script.log)
    exec 2>&1
    
    echo "[$(date)] ========================================"
    echo "[$(date)] Starting deployment process..."
    echo "[$(date)] ========================================"
    
    # Function for error handling
    handle_error() {
      echo "[$(date)] ERROR: $1" >&2
      exit 1
    }
    
    # Update system and install dependencies
    echo "[$(date)] Installing system dependencies..."
    apt-get update || handle_error "Failed to update package lists"
    apt-get install -y docker.io git curl wget || handle_error "Failed to install packages"
    
    echo "[$(date)] Starting Docker service..."
    systemctl start docker || handle_error "Failed to start Docker"
    systemctl enable docker || handle_error "Failed to enable Docker"
    
    # Install Docker Compose
    echo "[$(date)] Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || handle_error "Failed to download Docker Compose"
    chmod +x /usr/local/bin/docker-compose
    docker-compose --version || handle_error "Docker Compose installation failed"
    
    # Add ubuntu user to docker group
    echo "[$(date)] Configuring Docker permissions..."
    usermod -aG docker ubuntu
    
    # CRITICAL FIX: Configure git for ubuntu user BEFORE cloning
    echo "[$(date)] Configuring git globally..."
    # Set git configs that will apply to all operations
    git config --system --add safe.directory '*'
    git config --system user.email "deployment@gcp.vm"
    git config --system user.name "GCP Deployment"
    
    # Set up repository directory
    REPO_DIR="/home/ubuntu/app"
    echo "[$(date)] Setting up repository at $REPO_DIR..."
    
    # Create directory structure with proper ownership from the start
    mkdir -p "$REPO_DIR"
    chown ubuntu:ubuntu "$REPO_DIR"
    
    # Clone as ubuntu user (not root!) to avoid permission issues
    echo "[$(date)] Cloning repository as ubuntu user..."
    if [ -d "$REPO_DIR/.git" ]; then
      echo "[$(date)] Repository already exists. Updating..."
      # Run git operations as ubuntu user
      su - ubuntu -c "cd '$REPO_DIR' && git fetch origin" || handle_error "Failed to fetch"
      su - ubuntu -c "cd '$REPO_DIR' && git reset --hard origin/main" || handle_error "Failed to reset"
      su - ubuntu -c "cd '$REPO_DIR' && git pull" || handle_error "Failed to pull"
    else
      echo "[$(date)] Cloning fresh repository..."
      # Clone as ubuntu user
      su - ubuntu -c "git clone '${var.github_repo}' '$REPO_DIR'" || handle_error "Failed to clone"
    fi
    
    # Ensure ownership is correct (belt and suspenders approach)
    echo "[$(date)] Setting final permissions..."
    chown -R ubuntu:ubuntu "$REPO_DIR"
    chmod -R u+rw "$REPO_DIR"
    
    # Configure git in the repo directory
    su - ubuntu -c "cd '$REPO_DIR' && git config --local --add safe.directory '$REPO_DIR'"
    
    # Verify repository structure
    echo "[$(date)] Verifying repository structure..."
    if [ ! -d "$REPO_DIR/Deployee" ]; then
      handle_error "Deployee directory not found in repository"
    fi
    if [ ! -f "$REPO_DIR/Deployee/docker-compose.yml" ]; then
      handle_error "docker-compose.yml not found in Deployee directory"
    fi
    
    echo "[$(date)] Repository structure verified successfully"
    
    # Navigate to deployment directory
    cd "$REPO_DIR/Deployee" || handle_error "Failed to navigate to Deployee directory"
    echo "[$(date)] Current directory: $(pwd)"
    
    # Show docker-compose configuration
    echo "[$(date)] Docker Compose configuration:"
    cat docker-compose.yml
    
    # Pull images
    echo "[$(date)] Pulling Docker images..."
    docker-compose pull || echo "Warning: Some images may need to be built"
    
    # Build application
    echo "[$(date)] Building application Docker image..."
    docker-compose build --no-cache || handle_error "Failed to build application"
    
    # Stop any existing containers
    echo "[$(date)] Stopping any existing containers..."
    docker-compose down || true
    
    # Start containers
    echo "[$(date)] Starting containers..."
    docker-compose up -d || handle_error "Failed to start containers"
    
    # Wait for containers to be healthy
    echo "[$(date)] Waiting for containers to stabilize..."
    sleep 30
    
    # Show container status
    echo "[$(date)] Container status:"
    docker-compose ps
    
    # Test local access
    echo "[$(date)] Testing application..."
    if curl -f -s http://localhost:3000 > /dev/null 2>&1; then
      echo "[$(date)] ✓ Application is responding"
    else
      echo "[$(date)] WARNING: Application not responding yet (may need more time)"
      echo "[$(date)] Container logs:"
      docker-compose logs --tail=50
    fi
    
    # Get external IP
    EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google')
    
    # Create deployment info file readable by ubuntu user
    cat > /home/ubuntu/deployment-info.txt <<DEPLOY_INFO
======================================
DEPLOYMENT COMPLETED
======================================
Date: $(date)
Repository: ${var.github_repo}
Commit: $(git log -1 --oneline)
Direct URL: http://$EXTERNAL_IP:3000
======================================
DEPLOY_INFO
    
    chown ubuntu:ubuntu /home/ubuntu/deployment-info.txt
    
    echo "[$(date)] ========================================"
    echo "[$(date)] Deployment completed!"
    echo "[$(date)] ========================================"
    echo "[$(date)] Direct access URL: http://$EXTERNAL_IP:3000"
    echo "[$(date)] Logs: /var/log/startup-script.log"
    echo "[$(date)] Info: /home/ubuntu/deployment-info.txt"
    echo "[$(date)] ========================================"
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
  
  depends_on = [
    google_project_service.compute,
    google_compute_firewall.allow_http,
    google_compute_firewall.allow_https,
    google_compute_firewall.allow_health_check,
    google_compute_firewall.allow_ssh,
    google_compute_firewall.allow_app_port
  ]
}

# ============================================
# HEALTH CHECK
# ============================================

resource "google_compute_health_check" "nextjs_health_check" {
  name               = "todo-app-health-check"
  check_interval_sec = 30
  timeout_sec        = 10
  healthy_threshold  = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 3000
    request_path = "/api/health"
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
    google_compute_instance.nextjs_vm.self_link
  ]

  named_port {
    name = "http"
    port = 3000
  }

  depends_on = [google_compute_instance.nextjs_vm]
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
  description = "URL to access via Load Balancer"
  value       = "http://${google_compute_global_address.nextjs_ip.address}"
}

output "direct_vm_url" {
  description = "Direct VM access - WORKS IMMEDIATELY"
  value       = "http://${google_compute_instance.nextjs_vm.network_interface[0].access_config[0].nat_ip}:3000"
}

output "ssh_command" {
  description = "SSH into the VM"
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id}"
}

output "check_startup_logs" {
  description = "Check startup script logs"
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id} --command='sudo cat /var/log/startup-script.log'"
}

output "check_containers" {
  description = "Check container status"
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id} --command='cd /home/ubuntu/app/Deployee && sudo docker-compose ps'"
}

output "deployment_info" {
  description = "View deployment information"
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id} --command='cat /home/ubuntu/deployment-info.txt'"
}

output "access_summary" {
  description = "Access methods summary"
  value = {
    direct_access     = "✅ http://${google_compute_instance.nextjs_vm.network_interface[0].access_config[0].nat_ip}:3000 (Immediate)"
    load_balancer     = "⏳ http://${google_compute_global_address.nextjs_ip.address} (Wait 10 min)"
    ssh               = "✅ Port 22 (Enabled)"
    direct_port_3000  = "✅ Port 3000 (Open to Internet)"
  }
}
