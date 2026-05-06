# Finance Tracker — Jenkins CI/CD Pipeline Setup Guide

> **Stack:** Jenkins (Docker) → GitHub → Docker Hub → AWS EC2  
> **App:** React + Vite, served via nginx inside a Docker container

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      CI/CD Flow                                 │
│                                                                 │
│  GitHub Repo          Jenkins Agent           AWS EC2           │
│  ┌──────────┐  push   ┌──────────────────┐   ┌──────────────┐  │
│  │ docker1  │────────>│ 1. Checkout      │   │ Docker       │  │
│  │ (main)   │         │ 2. Install+Lint  │   │ container    │  │
│  └──────────┘         │ 3. Docker Build  │   │ :3000        │  │
│                       │ 4. Health Check  │   └──────────────┘  │
│  Docker Hub           │ 5. Push Image ───┼──>  Docker Hub       │
│  ┌──────────┐         │ 6. Deploy EC2 ───┼──>  EC2 (SSH+pull)  │
│  │ akshay   │         │ 7. Smoke Test    │                     │
│  │ 8969/... │         └──────────────────┘                     │
│  └──────────┘                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Jenkins | Running as Docker container with Docker socket mounted |
| Docker Hub account | `akshay8969` — already configured |
| AWS EC2 instance | Ubuntu, Docker installed, port 3000 open in Security Group |
| EC2 SSH key pair | `.pem` file available |

---

## Step 1 — Run Jenkins with Docker Socket Access

```bash
docker run -d \
  -p 8080:8080 \
  -p 50000:50000 \
  --name jenkins \
  --restart=on-failure \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts-jdk21
```

### Install Docker CLI inside Jenkins container

```bash
# Install Docker CLI
docker exec -u root jenkins bash -c "
  apt-get update && \
  apt-get install -y docker.io curl && \
  chmod 666 /var/run/docker.sock
"

# Verify Docker works inside Jenkins
docker exec jenkins docker ps
```

### Install required Jenkins plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:
- **Docker Pipeline**
- **SSH Agent**
- **Credentials Binding**
- **Timestamper**
- **Git**

---

## Step 2 — Configure Credentials in Jenkins

Navigate to: **Manage Jenkins → Credentials → (global) → Add Credentials**

### Credential 1 — Docker Hub

| Field | Value |
|---|---|
| Kind | Username with password |
| Username | `akshay8969` |
| Password | Your Docker Hub password / access token |
| ID | `dockerhub-credentials` ← **must match Jenkinsfile** |

### Credential 2 — EC2 SSH Key

| Field | Value |
|---|---|
| Kind | SSH Username with private key |
| Username | `ubuntu` (or `ec2-user` for Amazon Linux) |
| Private Key | Paste the contents of your `.pem` key file |
| ID | `ec2-ssh-key` ← **must match Jenkinsfile** |

---

## Step 3 — Configure EC2 Host (Global Environment Variable)

Go to **Manage Jenkins → System → Global properties → Environment variables**

| Name | Value |
|---|---|
| `EC2_HOST` | Your EC2 Public IP (e.g., `54.123.45.67`) |
| `EC2_USER` | `ubuntu` |

> Alternatively, edit the `EC2_HOST` value directly in the `Jenkinsfile`.

---

## Step 4 — Prepare the EC2 Instance

SSH into your EC2 instance and install Docker:

```bash
# Connect
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>

# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io

# Start Docker and allow ubuntu user to run it
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu

# Log out and back in for group change to take effect
exit
```

**Open EC2 Security Group inbound rules:**
- Port `22` (SSH) — from Jenkins agent IP
- Port `3000` (App) — from `0.0.0.0/0` (or your IP)

---

## Step 5 — Create the Jenkins Pipeline Job

1. Open Jenkins at `http://localhost:8080`
2. Click **New Item**
3. Name it `finance-tracker-pipeline` → Select **Pipeline** → Click **OK**
4. Under **Build Triggers**, optionally check:
   - ✅ **GitHub hook trigger for GITScm polling** (requires GitHub webhook)
   - Or: **Poll SCM** with schedule `H/5 * * * *` (poll every 5 min)
5. Scroll to **Pipeline** section:
   - **Definition:** `Pipeline script from SCM`
   - **SCM:** `Git`
   - **Repository URL:** `https://github.com/Unlicensed-Mystic/docker1.git`
   - **Branch Specifier:** `*/main`
   - **Script Path:** `Jenkinsfile`
6. Click **Save**

---

## Step 6 — Run the Pipeline

Click **Build Now** — the pipeline will execute these 7 stages:

| # | Stage | What Happens |
|---|---|---|
| 1 | **Checkout** | Pulls latest code from `main`; sets `IMAGE_TAG = BUILD_NUMBER-COMMIT` |
| 2 | **Install & Lint** | `npm ci` inside Node container; validates source files |
| 3 | **Build Docker Image** | `docker build` with OCI labels and two tags |
| 4 | **Health Validation** | Runs image locally on port `3001`; `curl` checks HTTP 200 (5 retries) |
| 5 | **Push to Docker Hub** | Pushes `:<tag>` and `:latest` to `akshay8969/finance-tracker` |
| 6 | **Deploy to EC2** | SSH → pull image → stop old container → start new with `--restart unless-stopped` |
| 7 | **Smoke Test (EC2)** | SSHes in; curls `localhost:3000` up to 5 times; prints logs on failure |

On **success**, the app is live at:
```
http://<EC2_PUBLIC_IP>:3000
```

---

## Troubleshooting

### ❌ `docker: command not found` in Jenkins

```bash
docker exec -u root jenkins apt-get install -y docker.io
docker exec -u root jenkins chmod 666 /var/run/docker.sock
```

### ❌ Health check fails (port already in use)

```bash
docker rm -f finance-tracker-healthcheck
```

### ❌ SSH connection to EC2 refused

- Ensure Security Group allows **port 22** from Jenkins agent IP
- Verify the `.pem` file is correctly pasted into the Jenkins credential

### ❌ Docker pull fails on EC2 (rate limit)

- Use a Docker Hub Personal Access Token instead of password
- Or add `--registry-mirror` to EC2's Docker daemon

### ❌ App returns 502 / blank page on EC2

```bash
# On EC2:
docker logs finance-tracker-app --tail 100
docker inspect finance-tracker-app
```

---

## Image Tagging Strategy

```
akshay8969/finance-tracker:<BUILD_NUMBER>-<SHORT_COMMIT>   ← immutable, traceable
akshay8969/finance-tracker:latest                          ← always points to newest
```

Every image is labelled with:
- `org.opencontainers.image.created`
- `org.opencontainers.image.revision` (git commit)
- `org.opencontainers.image.version`

---

## Pipeline Screenshots

<!-- Add your Jenkins build screenshots here -->

---

*Last updated: May 2026*
