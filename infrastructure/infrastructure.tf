# infrastructure.tf
# Complete GCP Infrastructure with Direct VM Access
# VM + Load Balancer + Docker Containers (Next.js + MongoDB)

variable "project_id" {
  description = "Your GCP Project ID"
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

# NEW: Allow direct access to application port 3000
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
    
    echo "[$(date)] Starting deployment..."
    
    # Update system
    apt-get update
    apt-get install -y docker.io git curl
    
    systemctl start docker
    systemctl enable docker
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Add ubuntu user to docker group
    usermod -aG docker ubuntu
    
    # Clone the GitHub repository
    echo "[$(date)] Cloning repository..."
    git clone ${var.github_repo} /home/ubuntu/todo_infrastructure
    
    # Create .env.local file (gitignored, so must be created manually)
    echo "[$(date)] Creating .env.local file..."
    cat > "/home/ubuntu/todo_infrastructure/Todo App/.env.local" <<'ENV_EOF'
MONGODB_URI=mongodb://mongodb:27017/todoapp
ENV_EOF
    
    # Create health check endpoint for Next.js
    echo "[$(date)] Creating health check endpoint..."
    mkdir -p "/home/ubuntu/todo_infrastructure/Todo App/app/api/health"
    cat > "/home/ubuntu/todo_infrastructure/Todo App/app/api/health/route.ts" <<'HEALTH_EOF'
export async function GET() {
  return new Response("OK", { status: 200 });
}
HEALTH_EOF
    
    # Set ownership
    chown -R ubuntu:ubuntu /home/ubuntu/todo_infrastructure
    
    # Navigate to Deployee directory
    cd /home/ubuntu/todo_infrastructure/Deployee
    
    # Pull images
    echo "[$(date)] Pulling Docker images..."
    docker-compose pull
    
    # Start containers
    echo "[$(date)] Starting containers..."
    docker-compose up -d
    
    # Wait for containers to be healthy
    echo "[$(date)] Waiting for containers to be healthy..."
    sleep 30
    
    # Show container status
    echo "[$(date)] Container status:"
    docker-compose ps
    
    # Test local access
    echo "[$(date)] Testing local access..."
    curl -s http://localhost:3000/api/health > /dev/null && echo "✓ App responding on port 3000" || echo "✗ App not responding"
    
    echo "[$(date)] Deployment completed!"
    
    # Get external IP
    EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google')
    echo "[$(date)] Direct access URL: http://$EXTERNAL_IP:3000"
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
  check_interval_sec = 10
  timeout_sec        = 5
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
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id} --command='cd /home/ubuntu/todo_infrastructure/Deployee && sudo docker-compose ps'"
}

output "check_backend_health" {
  description = "Check load balancer backend health"
  value       = "gcloud compute backend-services get-health todo-app-backend --global"
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
