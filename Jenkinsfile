// Declarative CI pipeline for HabitApp.
// Jenkins does CI only: build, test, scan, image, push, then commit the new image tag to the
// config repo. Argo CD (not Jenkins) deploys it. This file never calls kubectl or helm install.
//
// Jenkins setup this file expects:
//   Tools        : maven 'maven-3.9', jdk 'jdk-21'   (Manage Jenkins > Tools)
//   SonarQube    : server named 'sonarqube'          (Manage Jenkins > System)
//   Credentials  : 'dockerhub-creds' (Username with password: Docker Hub user + access token)
//                  'github-creds'    (Username with password: GitHub user + personal access token)
// No secret values appear here, only credential IDs.

pipeline {
    agent any

    tools {
        maven 'maven-3.9'
        jdk 'jdk-21'
    }

    environment {
        // Docker Hub repo for the image, and the GitOps config repo that Argo CD watches
        IMAGE_REPO      = 'narayanathota/habitapp'
        CONFIG_REPO_URL = 'https://github.com/narayanathota/HabitApp-config.git'
        CONFIG_BRANCH   = 'main'
        VALUES_FILE     = 'charts/habitapp/values.yaml'

        DOCKERHUB_CREDS = 'dockerhub-creds'
        GITHUB_CREDS    = 'github-creds'
        SONAR_SERVER    = 'sonarqube'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15'))
    }

    triggers {
        githubPush()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                sh 'git log -1 --oneline'
            }
        }

        stage('Maven Build') {
            steps {
                sh 'mvn -B clean package -DskipTests'
            }
        }

        stage('Unit Test') {
            steps {
                sh 'mvn -B test'
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv("${SONAR_SERVER}") {
                    // Server URL and token are injected by withSonarQubeEnv
                    sh 'mvn -B sonar:sonar'
                }
            }
        }

        stage('Quality Gate') {
            steps {
                // Needs the SonarQube webhook: http://<jenkins>:8080/sonarqube-webhook/
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Image Versioning') {
            steps {
                script {
                    def sha = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${sha}"
                    echo "Image will be ${env.IMAGE_REPO}:${env.IMAGE_TAG}"
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                      -t "$IMAGE_REPO:$IMAGE_TAG" \
                      -t "$IMAGE_REPO:build-$BUILD_NUMBER" .
                '''
            }
        }

        // Only the main branch publishes images and changes the deployment config
        stage('Push Image') {
            when { expression { env.GIT_BRANCH in ['origin/main', 'main'] } }
            steps {
                withCredentials([usernamePassword(credentialsId: "${DOCKERHUB_CREDS}",
                                                  usernameVariable: 'REG_USER',
                                                  passwordVariable: 'REG_PASS')]) {
                    // Single-quoted so the shell, not Groovy, reads the secrets (no leak in logs)
                    sh '''
                        echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin
                        docker push "$IMAGE_REPO:$IMAGE_TAG"
                        docker push "$IMAGE_REPO:build-$BUILD_NUMBER"
                        docker logout
                    '''
                }
            }
        }

        stage('Update Helm Configuration') {
            when { expression { env.GIT_BRANCH in ['origin/main', 'main'] } }
            steps {
                withCredentials([usernamePassword(credentialsId: "${GITHUB_CREDS}",
                                                  usernameVariable: 'GIT_USER',
                                                  passwordVariable: 'GIT_PASS')]) {
                    sh '''
                        rm -rf config-repo
                        git -c credential.helper='!f() { echo "username=$GIT_USER"; echo "password=$GIT_PASS"; }; f' \
                            clone --branch "$CONFIG_BRANCH" --depth 1 "$CONFIG_REPO_URL" config-repo

                        # Change only the image tag line in values.yaml
                        sed -i "s|^  tag: .*|  tag: \\"$IMAGE_TAG\\"|" "config-repo/$VALUES_FILE"
                        grep -n "^  tag:" "config-repo/$VALUES_FILE"
                    '''
                }
            }
        }

        stage('Commit Deployment Change') {
            when { expression { env.GIT_BRANCH in ['origin/main', 'main'] } }
            steps {
                withCredentials([usernamePassword(credentialsId: "${GITHUB_CREDS}",
                                                  usernameVariable: 'GIT_USER',
                                                  passwordVariable: 'GIT_PASS')]) {
                    sh '''
                        cd config-repo
                        git config user.name  "jenkins-ci"
                        git config user.email "jenkins-ci@users.noreply.github.com"
                        git add "$VALUES_FILE"
                        if git diff --cached --quiet; then
                            echo "values.yaml already has this tag, nothing to commit"
                        else
                            git commit -m "ci: deploy habitapp $IMAGE_TAG (build #$BUILD_NUMBER)"
                            git -c credential.helper='!f() { echo "username=$GIT_USER"; echo "password=$GIT_PASS"; }; f' \
                                push origin "$CONFIG_BRANCH"
                        fi
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Done. Argo CD will detect ${env.IMAGE_REPO}:${env.IMAGE_TAG} in the config repo and deploy it."
        }
        failure {
            echo 'Pipeline failed. Check the stage logs above.'
        }
        always {
            // Free disk on the agent
            sh 'docker rmi "$IMAGE_REPO:$IMAGE_TAG" "$IMAGE_REPO:build-$BUILD_NUMBER" || true'
            cleanWs()
        }
    }
}
