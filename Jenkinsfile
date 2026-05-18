pipeline {
    agent {
        label 'windows-docker'
    }

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    parameters {
        booleanParam(
            name: 'RUN_PLATFORM_SETUP',
            defaultValue: false,
            description: 'Install or update cluster-level add-ons such as Ingress Controller and Metrics Server'
        )
    }

    environment {
        REGISTRY = 'localhost:5001'
        IMAGE_NAME = 'petclinic-app'
        IMAGE_TAG = "v1.0.${BUILD_NUMBER}-local"
        FULL_IMAGE_NAME = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        NAMESPACE = 'petclinic-prod'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Tool Check') {
            steps {
                bat 'docker --version'
                bat 'kubectl version --client'
                bat 'kind --version'
                bat 'java -version'
                bat 'git --version'
                bat 'trivy --version'
            }
        }

        stage('Setup Platform Add-ons') {
            when {
                expression { return params.RUN_PLATFORM_SETUP }
            }
            steps {
                powershell '''
                $ErrorActionPreference = "Stop"

                Write-Host "Installing or updating platform add-ons..."

                if (Test-Path ".\\scripts\\install-ingress.ps1") {
                    .\\scripts\\install-ingress.ps1
                } else {
                    Write-Host "install-ingress.ps1 not found, skipping Ingress installation."
                }

                if (Test-Path ".\\scripts\\install-metrics-server.ps1") {
                    .\\scripts\\install-metrics-server.ps1
                } else {
                    Write-Host "install-metrics-server.ps1 NOT FOUND!!!, SKIPPING METRICS SERVER INSTALLATION!!!"
                }
                '''
            }
        }

        stage('Test Application') {
            steps {
                dir('app/spring-petclinic') {
                    bat 'mvnw.cmd clean test -B'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                bat 'docker build -t %FULL_IMAGE_NAME% -f docker/Dockerfile .'
            }
        }

        stage('Scan Docker Image with Trivy') {
            steps {
                bat 'trivy image --severity HIGH,CRITICAL --format table --output trivy-image-scan.txt %FULL_IMAGE_NAME%'
            }
        }

        stage('Push Image To Local Registry') {
            steps {
                bat 'docker push %FULL_IMAGE_NAME%'
            }
        }

        stage('Validate Kubernetes Manifests') {
            steps {
                bat 'kubectl kustomize k8s/base > rendered-manifests.yaml'
            }
        }

        stage('Deploy To Kubernetes') {
            steps {
                withCredentials([
                    string(credentialsId: 'petclinic-postgres-db', variable: 'POSTGRES_DB'),
                    string(credentialsId: 'petclinic-postgres-user', variable: 'POSTGRES_USER'),
                    string(credentialsId: 'petclinic-postgres-password', variable: 'POSTGRES_PASSWORD')
                ]) {
                    powershell '''
                    $ErrorActionPreference = "Stop"

                    kubectl apply -f k8s/base/namespace.yaml

                    $SecretDir = ".jenkins-secrets"
                    New-Item -ItemType Directory -Force -Path $SecretDir | Out-Null
                    Set-Content -Path "$SecretDir\\postgres.db" -Value $env:POSTGRES_DB -NoNewline
                    Set-Content -Path "$SecretDir\\postgres.user" -Value $env:POSTGRES_USER -NoNewline
                    Set-Content -Path "$SecretDir\\postgres.password" -Value $env:POSTGRES_PASSWORD -NoNewline
                    kubectl create secret generic petclinic-db-secret `
                      --namespace $env:NAMESPACE `
                      --from-file=postgres.db="$SecretDir\\postgres.db" `
                      --from-file=postgres.user="$SecretDir\\postgres.user" `
                      --from-file=postgres.password="$SecretDir\\postgres.password" `
                      --dry-run=client -o yaml | kubectl apply -f -

                    Remove-Item -Recurse -Force $SecretDir

                    kubectl apply -k k8s/base

                    kubectl set image deployment/petclinic-app `
                      petclinic-app=$env:FULL_IMAGE_NAME `
                      -n $env:NAMESPACE
                    '''
                }
            }
        }

        stage('Verify Rollout') {
            steps {
                bat 'kubectl rollout status deployment/petclinic-app -n %NAMESPACE% --timeout=180s'
                bat 'kubectl get pods,svc,ingress,hpa,pdb,networkpolicy -n %NAMESPACE%'
                bat 'kubectl describe deployment petclinic-app -n %NAMESPACE%'
            }
        }
    }

    post {
        success {
            echo 'SUCCESS!!! PIPELINE COMPLETED. http://localhost:8080'
        }

        failure {
            echo 'FAILED!!! PIPELINE FAILED. pls check Jenkins console output and Kubernetes logs'
            bat 'kubectl get pods -n %NAMESPACE%'
        }

        always {
            archiveArtifacts artifacts: 'rendered-manifests.yaml,trivy-image-scan.txt', allowEmptyArchive: true
        }
    }
}