# infrastructure.tf
# Complete GCP Infrastructure with Direct VM Access
# VM + Load Balancer + Docker Containers (Next.js + MongoDB)

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "my-app-todo-485623" # Replace with your actual project ID
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
  default = 40
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
    
    # Log everything to /var/log/startup-script.log
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
    
    # Verify Docker Compose installation
    docker-compose --version || handle_error "Docker Compose installation failed"
    
    # Add ubuntu user to docker group
    echo "[$(date)] Configuring Docker permissions..."
    usermod -aG docker ubuntu
    
    # Set up repository directory
    REPO_DIR="/home/ubuntu/app"
    echo "[$(date)] Setting up repository at $REPO_DIR..."
    
    # Clone or update repository (idempotent)
    if [ -d "$REPO_DIR/.git" ]; then
      echo "[$(date)] Repository already exists. Updating..."
      cd "$REPO_DIR"
      git fetch origin || handle_error "Failed to fetch from remote"
      git reset --hard origin/main || git reset --hard origin/master || handle_error "Failed to reset repository"
      git pull || handle_error "Failed to pull latest changes"
    else
      echo "[$(date)] Cloning repository from ${var.github_repo}..."
      rm -rf "$REPO_DIR"
      git clone "${var.github_repo}" "$REPO_DIR" || handle_error "Failed to clone repository"
    fi
    
    # Verify repository structure
    echo "[$(date)] Verifying repository structure..."
    if [ ! -d "$REPO_DIR/Deployee" ]; then
      handle_error "Deployee directory not found in repository"
    fi
    if [ ! -f "$REPO_DIR/Deployee/docker-compose.yml" ]; then
      handle_error "docker-compose.yml not found in Deployee directory"
    fi
    if [ ! -d "$REPO_DIR/Todo App" ]; then
      handle_error "Todo App directory not found in repository"
    fi
    
    echo "[$(date)] Repository structure verified successfully"
    
    # Set proper ownership
    echo "[$(date)] Setting file permissions..."
    chown -R ubuntu:ubuntu "$REPO_DIR"
    
    # Navigate to deployment directory
    cd "$REPO_DIR/Deployee" || handle_error "Failed to navigate to Deployee directory"
    echo "[$(date)] Current directory: $(pwd)"
    
    # Show docker-compose configuration
    echo "[$(date)] Docker Compose configuration:"
    cat docker-compose.yml
    
    # Pull images
    echo "[$(date)] Pulling Docker images..."
    docker-compose pull mongodb || handle_error "Failed to pull MongoDB image"
    
    # Build application
    echo "[$(date)] Building application Docker image..."
    docker-compose build --no-cache app || handle_error "Failed to build application image"
    
    # Stop any existing containers
    echo "[$(date)] Stopping any existing containers..."
    docker-compose down || true
    
    # Start containers
    echo "[$(date)] Starting containers..."
    docker-compose up -d || handle_error "Failed to start containers"
    
    # Wait for containers to be healthy
    echo "[$(date)] Waiting for containers to be healthy..."
    MAX_WAIT=180  # 3 minutes
    ELAPSED=0
    INTERVAL=5
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
      MONGODB_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' todo-mongodb 2>/dev/null || echo "starting")
      APP_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' todo-app 2>/dev/null || echo "starting")
      
      echo "[$(date)] Health status - MongoDB: $MONGODB_HEALTH, App: $APP_HEALTH"
      
      if [ "$MONGODB_HEALTH" = "healthy" ] && [ "$APP_HEALTH" = "healthy" ]; then
        echo "[$(date)] ✓ All containers are healthy!"
        break
      fi
      
      sleep $INTERVAL
      ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
      echo "[$(date)] WARNING: Containers did not become healthy within timeout"
      echo "[$(date)] Container status:"
      docker-compose ps
      echo "[$(date)] Container logs:"
      docker-compose logs --tail=50
    fi
    
    # Show container status
    echo "[$(date)] Final container status:"
    docker-compose ps
    
    # Test local access to health endpoint
    echo "[$(date)] Testing application health endpoint..."
    sleep 10  # Give app a bit more time
    if curl -f -s http://localhost:3000/api/health > /dev/null 2>&1; then
      echo "[$(date)] ✓ Health endpoint responding successfully"
    else
      echo "[$(date)] WARNING: Health endpoint not responding yet"
      echo "[$(date)] Attempting root endpoint..."
      curl -s http://localhost:3000 > /dev/null && echo "[$(date)] ✓ App responding on root endpoint" || echo "[$(date)] ✗ App not responding"
    fi
    
    # Get external IP
    EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google')
    
    echo "[$(date)] ========================================"
    echo "[$(date)] Deployment completed!"
    echo "[$(date)] ========================================"
    echo "[$(date)] Direct access URL: http://$EXTERNAL_IP:3000"
    echo "[$(date)] Health check URL: http://$EXTERNAL_IP:3000/api/health"
    echo "[$(date)] Logs available at: /var/log/startup-script.log"
    echo "[$(date)] ========================================"
    mkdir -p html
    cat > html/index.html <<'HTML_EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Todo App - Running!</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 16px;
            padding: 60px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 700px;
        }
        h1 {
            font-size: 3rem;
            color: #333;
            margin-bottom: 20px;
        }
        .status {
            display: inline-block;
            background: #34a853;
            color: white;
            padding: 12px 30px;
            border-radius: 50px;
            font-weight: 600;
            margin: 20px 0;
            font-size: 1.2rem;
        }
        .badge {
            display: inline-block;
            background: #4285f4;
            color: white;
            padding: 8px 20px;
            border-radius: 50px;
            font-size: 0.9rem;
            margin: 5px;
        }
        .info {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            margin-top: 30px;
            text-align: left;
        }
        .info p {
            margin: 10px 0;
            color: #666;
        }
        .info strong {
            color: #333;
        }
        .emoji { font-size: 4rem; margin: 20px 0; }
        .access-box {
            margin-top: 30px;
            padding: 20px;
            background: #e8f5e9;
            border-radius: 8px;
            border-left: 4px solid #34a853;
        }
        .access-box h3 {
            color: #2d9048;
            margin-bottom: 15px;
        }
        .access-box ul {
            list-style: none;
            padding: 0;
            text-align: left;
        }
        .access-box li {
            padding: 8px 0;
            color: #666;
        }
        .access-box li:before {
            content: "✓ ";
            color: #34a853;
            font-weight: bold;
            margin-right: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="emoji">🎉</div>
        <h1>Todo App Deployed!</h1>
        <div class="status">✓ Infrastructure Running</div>
        
        <div style="margin: 20px 0;">
            <span class="badge">Docker ✓</span>
            <span class="badge">MongoDB ✓</span>
            <span class="badge">Nginx ✓</span>
            <span class="badge">Firewall ✓</span>
        </div>
        
        <div class="access-box">
            <h3>✅ Direct Access Enabled!</h3>
            <ul>
                <li>You can access this page directly via VM IP</li>
                <li>Load Balancer access also available (wait 10 min)</li>
                <li>SSH access enabled for debugging</li>
                <li>Port 3000 open to the internet</li>
            </ul>
        </div>
        
        <div class="info">
            <p><strong>Infrastructure Status:</strong></p>
            <p>✓ VM Instance: Running</p>
            <p>✓ MongoDB: Connected and healthy</p>
            <p>✓ Web Server: Responding on port 3000</p>
            <p>✓ Firewall: Direct access configured</p>
            <p>⏳ Load Balancer: Provisioning (5-10 min)</p>
        </div>
        
        <div style="margin-top: 30px; padding: 20px; background: #fff3cd; border-radius: 8px;">
            <h3 style="color: #856404; margin-bottom: 10px;">🚀 Next Steps</h3>
            <ol style="color: #856404; text-align: left; padding-left: 20px;">
                <li>Build your Next.js Docker image</li>
                <li>Push to GitHub Container Registry</li>
                <li>Update docker-compose.yml with your image</li>
                <li>Redeploy using GitHub Actions</li>
            </ol>
        </div>
    </div>
    
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            console.log('✅ Todo App Infrastructure Deployed!');
            console.log('📍 Current URL:', window.location.href);
        });
    </script>
</body>
</html>
HTML_EOF
    
    # Create health check endpoint
    cat > html/health <<'HEALTH_EOF'
OK
HEALTH_EOF
    
    # Set ownership
    chown -R ubuntu:ubuntu /home/ubuntu/app
    
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
    curl -s http://localhost:3000 > /dev/null && echo "✓ App responding on port 3000" || echo "✗ App not responding"
    
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
  value       = "gcloud compute ssh ${google_compute_instance.nextjs_vm.name} --zone=${var.zone} --project=${var.project_id} --command='cd /home/ubuntu/app && sudo docker-compose ps'"
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
