# Todo Infrastructure

Full-stack Todo application with automated GCP infrastructure deployment using Terraform, Docker, and Next.js.

## Architecture

- **Frontend/Backend**: Next.js 14 (TypeScript, React 18, App Router)
- **Database**: MongoDB 7.0 with Mongoose ODM
- **Styling**: Tailwind CSS
- **Containerization**: Docker with multi-stage builds
- **Orchestration**: Docker Compose
- **Infrastructure**: Terraform for GCP
- **CI/CD**: GitHub Actions workflows

## Prerequisites

- [Google Cloud Platform Account](https://cloud.google.com/)
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Docker](https://www.docker.com/get-started) & Docker Compose
- [Node.js](https://nodejs.org/) >= 18
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)

## Project Structure

```
todo_infrastructure/
├── .github/
│   └── workflows/
│       ├── terraform-deploy.yml      # Deploy infrastructure
│       └── terraform-destroy.yml     # Destroy infrastructure
├── Deployee/
│   └── docker-compose.yml            # Production Docker setup
├── infrastructure/
│   └── infrastructure.tf             # GCP Terraform config
└── Todo App/
    ├── app/
    │   ├── api/
    │   │   ├── todos/                # CRUD API routes
    │   │   └── health/               # Health check endpoint
    │   ├── globals.css
    │   ├── layout.tsx
    │   └── page.tsx
    ├── components/
    │   ├── TodoForm.tsx
    │   ├── TodoItem.tsx
    │   └── TodoList.tsx
    ├── lib/
    │   └── mongodb.ts                # MongoDB connection
    ├── models/
    │   └── Todo.ts                   # Mongoose schema
    ├── Dockerfile                    # Multi-stage build
    ├── package.json
    └── .env.local                    # Environment variables (gitignored)
```

## Local Development

### 1. Clone the Repository

```bash
git clone https://github.com/kbimsara/todo_infrastructure.git
cd todo_infrastructure
```

### 2. Set Up Environment Variables

Create `.env.local` in the `Todo App/` directory:

```env
MONGODB_URI=mongodb://localhost:27017/todoapp
```

### 3. Run with Docker Compose

```bash
cd Deployee
docker-compose up -d
```

The application will be available at `http://localhost:3000`

### 4. Development Mode (Alternative)

```bash
cd "Todo App"
npm install
npm run dev
```

Make sure MongoDB is running locally on port 27017.

## GCP Deployment

### Infrastructure Components

- **Compute Engine VM**: Ubuntu 22.04 LTS (e2-medium)
- **Load Balancer**: Global HTTP(S) Load Balancer
- **Firewall Rules**: HTTP (80), HTTPS (443), SSH (22), App (3000)
- **Health Checks**: HTTP health checks on `/api/health`
- **Static IP**: Reserved global IP address

### Deployment Steps

#### 1. Configure GCP Project

```bash
# Authenticate with GCP
gcloud auth login
gcloud auth application-default login

# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID
```

#### 2. Update Terraform Variables

Edit `infrastructure/infrastructure.tf`:

```hcl
variable "project_id" {
  default = "your-project-id"  # Update this
}
```

#### 3. Deploy Infrastructure

```bash
cd infrastructure
terraform init
terraform plan
terraform apply
```

**Infrastructure Initialization:**

![Terraform Init Step 1](IMG/Infa%20init%201.png)
![Terraform Init Step 2](IMG/Infa%20init%202.png)

#### 4. Access Your Application

After deployment, Terraform outputs will show:

```
direct_vm_url = "http://VM_IP:3000"              # Available immediately
application_url = "http://LOAD_BALANCER_IP"     # Available in ~10 minutes
```

### What Happens During Deployment

The startup script automatically:

1. Installs Docker and Docker Compose
2. Clones this GitHub repository
3. Creates `.env.local` with correct MongoDB URI
4. Creates `/api/health` endpoint for health checks
5. Builds and starts Docker containers
6. Configures MongoDB and Next.js app

### Application Updates & Redeployment

Once your infrastructure is deployed, you can update the application code without recreating the entire infrastructure.

#### Method 1: Automatic Updates via GitHub Actions

When you push code changes to the `main` branch, the VM automatically pulls and deploys the latest code:

```bash
# Make your application changes
cd "Todo App"
# Edit components, add features, fix bugs...

# Commit and push to GitHub
git add .
git commit -m "Add new todo feature"
git push origin main

# Trigger GitHub Actions workflow (manual)
# OR it runs automatically if set up
```

**What Happens:**
1. GitHub Actions workflow triggers
2. Terraform imports existing infrastructure (no recreation)
3. VM detects code changes in startup script
4. Latest code is pulled from GitHub
5. Docker images rebuild with `--no-cache`
6. Containers restart with new code
7. Application serves updated version

**Timeline:**
- 0-2 min: Workflow starts and imports state
- 2-4 min: Terraform applies (VM preserved)
- 4-7 min: VM pulls code and rebuilds containers
- 7-10 min: Application healthy with new code

#### Method 2: Manual Update via SSH

For quick updates without triggering GitHub Actions:

```bash
# SSH into the VM
gcloud compute ssh todo-app-vm \
  --zone=us-central1-a \
  --project=your-project-id

# Once inside the VM:
cd /home/ubuntu/app

# Pull latest code from GitHub
git pull origin main

# Rebuild and restart containers
cd Deployee
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Verify containers are running
docker-compose ps

# Check application logs
docker-compose logs -f app
```

**Update Timeline:**
- ~1 min: Pull code from GitHub
- ~2-3 min: Rebuild Docker images
- ~30 sec: Restart containers
- **Total: ~4-5 minutes**

#### Method 3: Local Build & Push (Advanced)

Build locally and push images to a registry:

```bash
# Build image locally
cd "Todo App"
docker build -t gcr.io/your-project-id/todo-app:latest .

# Push to Google Container Registry
docker push gcr.io/your-project-id/todo-app:latest

# Update docker-compose.yml to use the image
# Then SSH and pull the new image
gcloud compute ssh todo-app-vm --zone=us-central1-a

# On VM:
cd /home/ubuntu/app/Deployee
docker-compose pull
docker-compose up -d
```

#### What Gets Preserved During Updates
- ✅ **MongoDB Data**: All todos and data persist in Docker volumes
- ✅ **VM IP Address**: No IP changes (direct URL stays same)
- ✅ **Load Balancer**: External IP remains constant
- ✅ **Configurations**: Firewall rules and network settings intact
- ✅ **SSL Certificates**: If configured, remain valid

#### What Gets Updated
- 🔄 **Application Code**: React components, API routes, styling
- 🔄 **Docker Images**: Rebuilt from latest code
- 🔄 **Dependencies**: `package.json` changes applied
- 🔄 **Environment Variables**: If modified in docker-compose.yml

#### Verify Application Update

```bash
# Check current git commit on VM
gcloud compute ssh todo-app-vm \
  --zone=us-central1-a \
  --command='cd /home/ubuntu/app && git log -1 --oneline'

# Check when containers were last recreated
gcloud compute ssh todo-app-vm \
  --zone=us-central1-a \
  --command='docker ps --format "table {{.Names}}\t{{.Status}}"'

# Test the application
curl http://YOUR_VM_IP:3000/api/health
```

#### Rollback to Previous Version

If an update causes issues:

```bash
# SSH into VM
gcloud compute ssh todo-app-vm --zone=us-central1-a

# On VM - rollback to previous commit
cd /home/ubuntu/app
git log --oneline  # Find previous commit hash
git reset --hard COMMIT_HASH

# Rebuild and restart
cd Deployee
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

#### Zero-Downtime Updates (Production)

For production, implement blue-green deployment:

1. Create a second VM with new code
2. Test thoroughly
3. Switch load balancer to new VM
4. Keep old VM as backup
5. Destroy old VM after verification

#### Common Update Scenarios

**Frontend Changes Only:**
```bash
# Edit React components in Todo App/components/
# Push to GitHub → Auto-deploy or manual SSH update
# ~4-5 min total update time
```

**API Changes:**
```bash
# Edit routes in Todo App/app/api/
# Update may require schema changes
# Test thoroughly before deploying
```

**Database Schema Changes:**
```bash
# Update models in Todo App/models/
# May require data migration script
# Consider backup before updating
```

**Dependency Updates:**
```bash
# Update package.json
# Rebuild ensures all deps are fresh
# Test locally first with docker-compose
```

## Monitoring & Debugging

### Check Startup Logs

```bash
gcloud compute ssh todo-app-vm \
  --zone=us-central1-a \
  --project=your-project-id \
  --command='sudo cat /var/log/startup-script.log'
```

### Check Container Status

```bash
gcloud compute ssh todo-app-vm \
  --zone=us-central1-a \
  --project=your-project-id \
  --command='cd /home/ubuntu/todo_infrastructure/Deployee && sudo docker-compose ps'
```

### Check Load Balancer Health

```bash
gcloud compute backend-services get-health todo-app-backend --global
```

### SSH into VM

```bash
gcloud compute ssh todo-app-vm \
  --zone=us-central1-a \
  --project=your-project-id
```

## Tech Stack

### Frontend
- **Next.js 14**: React framework with App Router
- **TypeScript**: Type-safe development
- **Tailwind CSS**: Utility-first CSS framework
- **React 18**: UI library

### Backend
- **Next.js API Routes**: Serverless API endpoints
- **MongoDB**: NoSQL database
- **Mongoose**: ODM for MongoDB

### DevOps
- **Docker**: Containerization
- **Docker Compose**: Multi-container orchestration
- **Terraform**: Infrastructure as Code
- **GitHub Actions**: CI/CD automation
- **GCP**: Cloud platform

## Features

### Application Features
- ✅ Create, Read, Update, Delete todos
- ✅ Filter todos (All / Active / Completed)
- ✅ Real-time statistics
- ✅ Responsive UI design
- ✅ Health check endpoints

### DevOps Features
- ✅ Production-ready Docker setup
- ✅ Automated GCP deployment via GitHub Actions
- ✅ Zero-downtime redeployment on git push
- ✅ Smart infrastructure state management
- ✅ Load balancing and auto-healing
- ✅ Automated health monitoring
- ✅ Infrastructure as Code (Terraform)

## Cleanup

To destroy all GCP resources:

```bash
cd infrastructure
terraform destroy
```

**Infrastructure Cleanup:**

![Terraform Destroy](IMG/Infa%20clean.png)

Or use the GitHub Actions workflow: `terraform-destroy.yml`

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/todos` | Get all todos |
| POST | `/api/todos` | Create a new todo |
| PUT | `/api/todos/[id]` | Update a todo |
| DELETE | `/api/todos/[id]` | Delete a todo |
| GET | `/api/health` | Health check |

## Security Notes

- MongoDB runs in Docker network (not exposed externally)
- Environment variables managed securely
- Firewall rules restrict access appropriately
- Health checks from GCP IP ranges only

## License

This project is open source and available under the MIT License.

## Author

**kbimsara**

- GitHub: [@kbimsara](https://github.com/kbimsara)
- Repository: [todo_infrastructure](https://github.com/kbimsara/todo_infrastructure)

## Contributing

Contributions, issues, and feature requests are welcome!

---

**Note**: Make sure to update the `project_id` in `infrastructure/infrastructure.tf` before deploying to GCP.
