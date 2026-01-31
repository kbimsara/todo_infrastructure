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

- Create, Read, Update, Delete todos
- Filter todos (All / Active / Completed)
- Real-time statistics
- Responsive UI design
- Health check endpoints
- Production-ready Docker setup
- Automated GCP deployment
- Load balancing and auto-healing

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
