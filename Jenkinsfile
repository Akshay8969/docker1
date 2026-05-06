// ============================================================
//  Finance Tracker — Production CI/CD Pipeline
//  Stages:
//    1. Checkout          — Pull latest source from GitHub
//    2. Build Image       — docker build with build number tag
//    3. Health Check      — Spin up local test container & curl
//    4. Push to Registry  — docker push to Docker Hub
//    5. Deploy to EC2     — SSH into instance, pull & restart
//    6. Smoke Test (EC2)  — Verify the live endpoint responds
// ============================================================

pipeline {
    agent any

    // ── Configurable variables ─────────────────────────────
    environment {
        // Docker Hub image (set DOCKERHUB_CREDENTIALS in Jenkins → Credentials)
        IMAGE_NAME      = 'akshay8969/finance-tracker'
        CONTAINER_NAME  = 'finance-tracker-app'

        // Port the app is served on (nginx inside container → 80)
        APP_PORT        = '3000'

        // Temporary local container used only during the health-check stage
        TEST_CONTAINER  = 'finance-tracker-healthcheck'
        TEST_PORT       = '3001'

        // EC2 connection details
        // EC2_HOST   — public IP / DNS of your EC2 instance
        // EC2_USER   — SSH username (e.g. ubuntu, ec2-user)
        // Set these as Jenkins environment variables or replace inline.
        EC2_HOST        = "${env.EC2_HOST ?: 'YOUR_EC2_PUBLIC_IP'}"
        EC2_USER        = "${env.EC2_USER ?: 'ubuntu'}"

        // Jenkins Credential IDs (configure via Jenkins → Manage Credentials)
        // DOCKERHUB_CREDENTIALS → Username/Password credential for Docker Hub
        // EC2_SSH_KEY           → SSH Private Key credential for EC2
        DOCKERHUB_CRED_ID = 'dockerhub-credentials'
        EC2_CRED_ID       = 'ec2-ssh-key'
    }

    options {
        // Keep only the last 10 build logs
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Fail the entire pipeline if any stage takes longer than 20 min
        timeout(time: 20, unit: 'MINUTES')
        // Timestamps in console output
        timestamps()
        // Prevent concurrent builds on the same branch
        disableConcurrentBuilds()
    }

    stages {

        // ── Stage 1: Checkout ───────────────────────────────
        stage('Checkout') {
            steps {
                echo '📥  Pulling latest source code from GitHub...'
                git branch: 'main',
                    url: 'https://github.com/Unlicensed-Mystic/docker1.git'
                echo "✅  Checked out commit: ${env.GIT_COMMIT?.take(7) ?: 'N/A'}"
            }
        }

        // ── Stage 2: Build Docker Image ─────────────────────
        stage('Build Docker Image') {
            steps {
                echo "🔨  Building Docker image: ${IMAGE_NAME}:${BUILD_NUMBER}"
                sh """
                    docker build \
                        --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \
                        --build-arg VCS_REF=${env.GIT_COMMIT ?: 'unknown'} \
                        -t ${IMAGE_NAME}:${BUILD_NUMBER} \
                        -t ${IMAGE_NAME}:latest \
                        .
                """
                echo "✅  Image built successfully → ${IMAGE_NAME}:${BUILD_NUMBER}"
            }
        }

        // ── Stage 3: Health Validation ──────────────────────
        stage('Health Validation') {
            steps {
                echo '🩺  Starting temporary container for health validation...'

                // Clean up any leftover test container
                sh "docker rm -f ${TEST_CONTAINER} || true"

                // Run the freshly built image on a dedicated test port
                sh """
                    docker run -d \
                        -p ${TEST_PORT}:80 \
                        --name ${TEST_CONTAINER} \
                        ${IMAGE_NAME}:${BUILD_NUMBER}
                """

                // Give nginx a moment to fully start
                sh 'sleep 5'

                // HTTP health check — exit non-zero if not 200
                sh """
                    echo '🔍  Probing http://localhost:${TEST_PORT} ...'
                    STATUS=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${TEST_PORT})
                    echo "    HTTP status: \$STATUS"
                    if [ "\$STATUS" != "200" ]; then
                        echo "❌  Health check FAILED (HTTP \$STATUS)"
                        exit 1
                    fi
                    echo '✅  Health check PASSED'
                """
            }
            post {
                always {
                    // Always remove the test container, pass or fail
                    sh "docker rm -f ${TEST_CONTAINER} || true"
                    echo '🧹  Test container removed.'
                }
            }
        }

        // ── Stage 4: Push to Docker Hub ─────────────────────
        stage('Push to Docker Hub') {
            steps {
                echo "📤  Pushing ${IMAGE_NAME} to Docker Hub..."
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CRED_ID}",
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"
                    sh "docker push ${IMAGE_NAME}:${BUILD_NUMBER}"
                    sh "docker push ${IMAGE_NAME}:latest"
                    sh "docker logout"
                }
                echo "✅  Image pushed → ${IMAGE_NAME}:${BUILD_NUMBER} & :latest"
            }
        }

        // ── Stage 5: Deploy to EC2 ──────────────────────────
        stage('Deploy to EC2') {
            steps {
                echo "🚀  Deploying to EC2 instance at ${EC2_HOST}..."
                withCredentials([sshUserPrivateKey(
                    credentialsId: "${EC2_CRED_ID}",
                    keyFileVariable: 'SSH_KEY'
                )]) {
                    sh """
                        ssh -i \$SSH_KEY \
                            -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=30 \
                            ${EC2_USER}@${EC2_HOST} '

                            echo "== [EC2] Logging into Docker Hub =="
                            echo "${DOCKER_PASS_PLACEHOLDER}" | docker login -u "${DOCKER_USER_PLACEHOLDER}" --password-stdin 2>/dev/null || true

                            echo "== [EC2] Pulling latest image =="
                            docker pull ${IMAGE_NAME}:latest

                            echo "== [EC2] Stopping old container =="
                            docker stop ${CONTAINER_NAME} 2>/dev/null || true
                            docker rm   ${CONTAINER_NAME} 2>/dev/null || true

                            echo "== [EC2] Starting new container =="
                            docker run -d \
                                -p ${APP_PORT}:80 \
                                --name ${CONTAINER_NAME} \
                                --restart always \
                                ${IMAGE_NAME}:latest

                            echo "== [EC2] Container status =="
                            docker ps --filter name=${CONTAINER_NAME} \
                                --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                        '
                    """
                }
                echo "✅  Deployment to EC2 complete."
            }
        }

        // ── Stage 6: Smoke Test on EC2 ──────────────────────
        stage('Smoke Test (EC2)') {
            steps {
                echo "🌐  Running smoke test against live EC2 endpoint..."

                // Wait a few seconds for the container to fully start
                sh 'sleep 8'

                withCredentials([sshUserPrivateKey(
                    credentialsId: "${EC2_CRED_ID}",
                    keyFileVariable: 'SSH_KEY'
                )]) {
                    sh """
                        ssh -i \$SSH_KEY \
                            -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=30 \
                            ${EC2_USER}@${EC2_HOST} '

                            STATUS=\$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT})
                            echo "Live endpoint HTTP status: \$STATUS"
                            if [ "\$STATUS" != "200" ]; then
                                echo "❌  Smoke test FAILED on EC2 (HTTP \$STATUS)"
                                exit 1
                            fi
                            echo "✅  Smoke test PASSED — app is live!"
                        '
                    """
                }
            }
        }

    } // end stages

    // ── Post-build actions ──────────────────────────────────
    post {
        success {
            echo """
╔══════════════════════════════════════════════════════════╗
║  🎉  Pipeline #${BUILD_NUMBER} completed SUCCESSFULLY!    ║
║                                                          ║
║  Image   : ${IMAGE_NAME}:${BUILD_NUMBER}                 ║
║  Live at : http://${EC2_HOST}:${APP_PORT}                ║
╚══════════════════════════════════════════════════════════╝
"""
        }
        failure {
            echo """
╔══════════════════════════════════════════════════════════╗
║  ❌  Pipeline #${BUILD_NUMBER} FAILED.                    ║
║  Review the console output above for root cause.         ║
╚══════════════════════════════════════════════════════════╝
"""
            // Clean up any dangling test containers on failure
            sh "docker rm -f ${TEST_CONTAINER} || true"
        }
        always {
            echo '🧹  Cleaning up dangling Docker images on Jenkins agent...'
            sh 'docker image prune -f || true'
        }
    }
}
