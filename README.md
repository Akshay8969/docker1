# Personal Finance Tracker - Docker & Jenkins CI/CD Deployment

This repository contains the source code, Docker configuration, and the fully automated Jenkins CI/CD Pipeline for the Personal Finance Tracker application.

---

## 🌐 Live Deployment (AWS EC2)

**Public URL:** [http://16.171.250.60:3000](http://16.171.250.60:3000)

> Hosted on an AWS EC2 `t2.micro` instance (Ubuntu) via an automated Jenkins Pipeline.

---

## ⚙️ Automated CI/CD Pipeline (Jenkins)

This project features a complete, 7-stage CI/CD pipeline (`Jenkinsfile`) that automates:
1. **Source Checkout** from GitHub.
2. **NPM Install & Linting** inside an ephemeral Node container.
3. **Multi-stage Docker Build** with OCI labels.
4. **Health Validation** on a local test container (HTTP 200 check).
5. **Pushing** the verified image to Docker Hub.
6. **Automated SSH Deployment** to AWS EC2 (pulls new image, stops old container, runs new container on port 3000).
7. **Production Smoke Test** against the live EC2 endpoint.

For detailed setup instructions, see the [CICD_PIPELINE_SETUP.md](./CICD_PIPELINE_SETUP.md) guide.

---

## 🐳 DockerHub

- **DockerHub Repository:** [https://hub.docker.com/r/akshay8969/finance-tracker](https://hub.docker.com/r/akshay8969/finance-tracker)

```bash
docker pull akshay8969/finance-tracker:latest
```

---

## 💻 Run Locally

To run the application manually on your local machine:

```bash
docker pull akshay8969/finance-tracker:latest
docker run -d -p 8080:80 --name finance-tracker akshay8969/finance-tracker:latest
```

Visit: [http://localhost:8080](http://localhost:8080)

---

## 📁 Repository Contents

| File/Folder | Description |
|---|---|
| `Jenkinsfile` | Declarative Jenkins CI/CD pipeline configuration |
| `CICD_PIPELINE_SETUP.md`| Comprehensive guide to setting up the CI/CD architecture |
| `Dockerfile` | Multi-stage build (Node 20 Alpine → Nginx Alpine) |
| `nginx.conf` | Custom Nginx config for React SPA routing |
| `src/` | React + Vite application source code |
| `FintrackDockerScreenshots/` | Screenshots of Website, image, docker and EC2 instance |
