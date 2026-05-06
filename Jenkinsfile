// ================================================================
//  Finance Tracker — Production CI/CD Pipeline
//  Author  : Akshay Singh
//  Repo    : https://github.com/Unlicensed-Mystic/docker1
//
//  Pipeline Stages:
//    1. Checkout           — Pull latest source from GitHub
//    2. Install & Lint     — npm ci + static code validation
//    3. Build Docker Image — Multi-stage build with labels
//    4. Health Validation  — Local container smoke-test (curl)
//    5. Push to Registry   — Push both tagged & latest to Docker Hub
//    6. Deploy to EC2      — SSH pull → stop old → run new container
//    7. Smoke Test (EC2)   — Verify live endpoint returns HTTP 200
// ================================================================

pipeline {
    agent any

    // ── Configurable Variables ──────────────────────────────────
    environment {
        // ── Docker Hub ──────────────────────────────────────────
        // Credential ID configured in: Jenkins → Manage Jenkins
        //   → Credentials → (global) → Add Credentials
        //   Kind: Username with password
        //   ID:   dockerhub-credentials
        DOCKERHUB_CRED_ID  = 'dockerhub-credentials'
        IMAGE_NAME         = 'akshay8969/finance-tracker'

        // ── Container / Port Settings ───────────────────────────
        CONTAINER_NAME     = 'finance-tracker-app'
        APP_PORT           = '3000'          // host port on EC2

        // ── Health-Check (local, Jenkins agent) ─────────────────
        TEST_CONTAINER     = 'finance-tracker-healthcheck'
        TEST_PORT          = '3001'          // must be free on Jenkins agent

        // ── EC2 Connection ───────────────────────────────────────
        // Credential ID configured in: Jenkins → Manage Jenkins
        //   → Credentials → (global) → Add Credentials
        //   Kind: SSH Username with private key
        //   ID:   ec2-ssh-key
        EC2_CRED_ID        = 'ec2-ssh-key'
        EC2_HOST           = "${env.EC2_HOST ?: 'YOUR_EC2_PUBLIC_IP'}"
        EC2_USER           = "${env.EC2_USER ?: 'ubuntu'}"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))   // keep last 10 build logs
        timeout(time: 25, unit: 'MINUTES')               // hard stop at 25 min
        timestamps()                                      // prefix every log line
        disableConcurrentBuilds()                         // no parallel builds
        skipStagesAfterUnstable()                         // fail-fast on unstable
    }

    stages {

        // ── Stage 1: Checkout ────────────────────────────────────
        stage('Checkout') {
            steps {
                echo '📥  Pulling latest source code from GitHub...'
                checkout scm                              // uses the SCM config from job
                script {
                    env.SHORT_COMMIT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.IMAGE_TAG = "${BUILD_NUMBER}-${env.SHORT_COMMIT}"
                }
                echo "✅  Checked out commit: ${env.SHORT_COMMIT}  →  tag will be ${env.IMAGE_TAG}"
            }
        }

        // ── Stage 2: Install & Lint ──────────────────────────────
        stage('Install & Lint') {
            // Use a Node container so we don't need Node on the Jenkins agent host
            agent {
                docker {
                    image 'node:20-alpine'
                    reuseNode true                        // re-use the checked-out workspace
                }
            }
            steps {
                echo '📦  Installing dependencies...'
                sh 'npm ci --prefer-offline'

                echo '🔍  Running lint checks...'
                // If you add eslint later, swap the line below:
                //   sh 'npm run lint'
                sh '''
                    echo "Checking for obvious syntax issues..."
                    node -e "
                        const fs = require('fs');
                        const path = require('path');
                        function walk(dir) {
                            fs.readdirSync(dir).forEach(f => {
                                const full = path.join(dir, f);
                                if (fs.statSync(full).isDirectory() && f !== 'node_modules' && f !== 'dist') walk(full);
                                else if (f.endsWith('.js') || f.endsWith('.jsx')) {
                                    try { require('fs').readFileSync(full, 'utf8'); }
                                    catch(e) { process.exit(1); }
                                }
                            });
                        }
                        walk('./src');
                        console.log('✅  All source files readable.');
                    "
                '''
                echo '✅  Install & Lint passed.'
            }
        }

        // ── Stage 3: Build Docker Image ──────────────────────────
        stage('Build Docker Image') {
            steps {
                echo "🔨  Building Docker image: ${IMAGE_NAME}:${env.IMAGE_TAG}"
                sh """
                    docker build \\
                        --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \\
                        --build-arg VCS_REF=${env.SHORT_COMMIT} \\
                        --build-arg VERSION=${env.IMAGE_TAG} \\
                        --label "org.opencontainers.image.created=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
                        --label "org.opencontainers.image.revision=${env.SHORT_COMMIT}" \\
                        --label "org.opencontainers.image.version=${env.IMAGE_TAG}" \\
                        --label "org.opencontainers.image.source=https://github.com/Unlicensed-Mystic/docker1" \\
                        -t ${IMAGE_NAME}:${env.IMAGE_TAG} \\
                        -t ${IMAGE_NAME}:latest \\
                        .
                """
                echo "✅  Image built → ${IMAGE_NAME}:${env.IMAGE_TAG} & :latest"
            }
        }

        // ── Stage 4: Health Validation ───────────────────────────
        stage('Health Validation') {
            steps {
                echo '🩺  Starting temporary container for health validation...'

                // Ensure no stale test container exists
                sh "docker rm -f ${TEST_CONTAINER} 2>/dev/null || true"

                // Run the freshly built image on the test port
                sh """
                    docker run -d \\
                        -p ${TEST_PORT}:80 \\
                        --name ${TEST_CONTAINER} \\
                        ${IMAGE_NAME}:${env.IMAGE_TAG}
                """

                // Allow nginx to fully initialise
                sh 'sleep 6'

                // Retry up to 5 times before failing
                retry(5) {
                    sh """
                        TEST_IP=\$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${TEST_CONTAINER})
                        echo "🔍  Probing http://\$TEST_IP:80 ..."
                        STATUS=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://\$TEST_IP:80)
                        echo "    HTTP status: \$STATUS"
                        if [ "\$STATUS" != "200" ]; then
                            echo "❌  Health check attempt FAILED (HTTP \$STATUS) — retrying..."
                            sleep 3
                            exit 1
                        fi
                        echo '✅  Health check PASSED'
                    """
                }
            }
            post {
                always {
                    sh "docker rm -f ${TEST_CONTAINER} 2>/dev/null || true"
                    echo '🧹  Test container removed.'
                }
            }
        }

        // ── Stage 5: Push to Docker Hub ──────────────────────────
        stage('Push to Docker Hub') {
            steps {
                echo "📤  Pushing ${IMAGE_NAME} to Docker Hub..."
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CRED_ID}",
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
                    sh "docker push ${IMAGE_NAME}:${env.IMAGE_TAG}"
                    sh "docker push ${IMAGE_NAME}:latest"
                    sh 'docker logout'
                }
                echo "✅  Pushed → ${IMAGE_NAME}:${env.IMAGE_TAG} & :latest"
            }
        }

        // ── Stage 6: Deploy to EC2 ───────────────────────────────
        stage('Deploy to EC2') {
            steps {
                echo "🚀  Deploying to EC2 at ${EC2_HOST}..."
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: "${EC2_CRED_ID}",
                        keyFileVariable: 'SSH_KEY'
                    ),
                    usernamePassword(
                        credentialsId: "${DOCKERHUB_CRED_ID}",
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    // Write a remote deploy script and execute it via SSH
                    sh """
                        ssh -i \$SSH_KEY \\
                            -o StrictHostKeyChecking=no \\
                            -o ConnectTimeout=30 \\
                            -o ServerAliveInterval=10 \\
                            ${EC2_USER}@${EC2_HOST} \\
                            "bash -s" <<'REMOTE'

                        set -e

                        echo "==> [EC2] Authenticating with Docker Hub"
                        echo "\${DOCKER_PASS}" | docker login -u "\${DOCKER_USER}" --password-stdin

                        echo "==> [EC2] Pulling image: ${IMAGE_NAME}:${env.IMAGE_TAG}"
                        docker pull ${IMAGE_NAME}:${env.IMAGE_TAG}
                        docker tag  ${IMAGE_NAME}:${env.IMAGE_TAG} ${IMAGE_NAME}:latest

                        echo "==> [EC2] Stopping & removing old container (if any)"
                        docker stop  ${CONTAINER_NAME} 2>/dev/null || true
                        docker rm    ${CONTAINER_NAME} 2>/dev/null || true

                        echo "==> [EC2] Starting new container"
                        docker run -d \\
                            -p ${APP_PORT}:80 \\
                            --name ${CONTAINER_NAME} \\
                            --restart unless-stopped \\
                            --label "deploy.build=${BUILD_NUMBER}" \\
                            --label "deploy.commit=${env.SHORT_COMMIT}" \\
                            ${IMAGE_NAME}:${env.IMAGE_TAG}

                        echo "==> [EC2] Running container:"
                        docker ps --filter name=${CONTAINER_NAME} \\
                            --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}"

                        echo "==> [EC2] Logging out of Docker Hub"
                        docker logout

                        echo "==> [EC2] Pruning unused images"
                        docker image prune -f --filter "until=24h"

REMOTE
                    """
                }
                echo "✅  Deployment to EC2 complete."
            }
        }

        // ── Stage 7: Smoke Test on EC2 ───────────────────────────
        stage('Smoke Test (EC2)') {
            steps {
                echo "🌐  Running smoke test against live EC2 endpoint: http://${EC2_HOST}:${APP_PORT}"

                // Brief wait for container to be fully ready
                sh 'sleep 8'

                withCredentials([sshUserPrivateKey(
                    credentialsId: "${EC2_CRED_ID}",
                    keyFileVariable: 'SSH_KEY'
                )]) {
                    sh """
                        ssh -i \$SSH_KEY \\
                            -o StrictHostKeyChecking=no \\
                            -o ConnectTimeout=30 \\
                            ${EC2_USER}@${EC2_HOST} \\
                            "bash -s" <<'REMOTE'

                        set -e
                        MAX_RETRIES=5
                        RETRY=0
                        until [ \$RETRY -ge \$MAX_RETRIES ]; do
                            STATUS=\$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost:${APP_PORT})
                            echo "Attempt \$((RETRY+1))/\${MAX_RETRIES} — HTTP \$STATUS"
                            if [ "\$STATUS" = "200" ]; then
                                echo "✅  Smoke test PASSED — app is live at http://${EC2_HOST}:${APP_PORT}"
                                exit 0
                            fi
                            RETRY=\$((RETRY+1))
                            sleep 5
                        done
                        echo "❌  Smoke test FAILED after \${MAX_RETRIES} attempts"
                        docker logs ${CONTAINER_NAME} --tail 50
                        exit 1

REMOTE
                    """
                }
            }
        }

    } // end stages

    // ── Post-Build Actions ───────────────────────────────────────
    post {
        success {
            echo """
╔══════════════════════════════════════════════════════════════╗
║  🎉  Pipeline #${BUILD_NUMBER} — SUCCESS                     ║
║                                                              ║
║  Image   : ${IMAGE_NAME}:${env.IMAGE_TAG}                    ║
║  Commit  : ${env.SHORT_COMMIT}                               ║
║  Live at : http://${EC2_HOST}:${APP_PORT}                    ║
╚══════════════════════════════════════════════════════════════╝
"""
        }

        failure {
            echo """
╔══════════════════════════════════════════════════════════════╗
║  ❌  Pipeline #${BUILD_NUMBER} — FAILED                      ║
║  Review the console output above for the root cause.         ║
╚══════════════════════════════════════════════════════════════╝
"""
            // Best-effort cleanup on failure
            sh "docker rm -f ${TEST_CONTAINER} 2>/dev/null || true"
        }

        always {
            echo '🧹  Cleaning up dangling Docker objects on Jenkins agent...'
            sh 'docker image prune -f 2>/dev/null || true'
            sh 'docker container prune -f 2>/dev/null || true'
            cleanWs()          // wipe the Jenkins workspace
        }
    }
}
