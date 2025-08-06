pipeline {
    agent any
    
    environment {
        // Docker configuration to fix the TLS issue
        DOCKER_HOST = 'unix:///var/run/docker.sock'
        DOCKER_TLS_VERIFY = ''
        DOCKER_CERT_PATH = ''
        
        // AWS and application configuration
        AWS_DEFAULT_REGION = 'us-west-2'
        ECR_REPOSITORY = '603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks'
        CLUSTER_NAME = 'capgemini-eks'
    }
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', 
                    url: 'https://github.com/Divya12377/Blue-Green1301.git'
            }
        }
        
        stage('Wait for Docker Daemon') {
            steps {
                script {
                    sh '''
                        export DOCKER_TLS_VERIFY=""
                        export DOCKER_HOST="unix:///var/run/docker.sock"
                        echo "Waiting for Docker daemon to be ready..."
                        for i in {1..30}; do
                            if docker info >/dev/null 2>&1; then
                                echo "Docker daemon is ready!"
                                break
                            fi
                            echo "Waiting for Docker daemon... ($i/30)"
                            sleep 10
                        done
                        
                        # Verify Docker is working
                        docker info
                    '''
                }
            }
        }
        
        stage('Verify Environment') {
            steps {
                script {
                    sh '''
                        export DOCKER_TLS_VERIFY=""
                        export DOCKER_HOST="unix:///var/run/docker.sock"
                        echo "Checking Docker installation..."
                        docker --version || { echo "Docker not found!"; exit 1; }
                        
                        echo "Checking AWS CLI..."
                        aws --version || { echo "AWS CLI not found!"; exit 1; }
                        
                        echo "Checking kubectl..."
                        kubectl version --client || { echo "kubectl not found!"; exit 1; }
                        
                        echo "Verifying workspace contents..."
                        ls -la
                        ls -la app/ || { echo "App directory not found!"; exit 1; }
                    '''
                }
            }
        }
        
        stage('AWS ECR Login') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', 
                                credentialsId: 'aws-credentials']]) {
                    script {
                        sh '''
                            export DOCKER_TLS_VERIFY=""
                            export DOCKER_HOST="unix:///var/run/docker.sock"
                            echo "Logging into AWS ECR..."
                            aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ECR_REPOSITORY}
                        '''
                    }
                }
            }
        }
        
        stage('Build Docker Images') {
            steps {
                script {
                    sh '''
                        export DOCKER_TLS_VERIFY=""
                        export DOCKER_HOST="unix:///var/run/docker.sock"
                        echo "Building Blue version..."
                        cd app
                        docker build -t ${ECR_REPOSITORY}:blue \
                            --build-arg APP_COLOR=blue .
                    '''
                    
                    sh '''
                        export DOCKER_TLS_VERIFY=""
                        export DOCKER_HOST="unix:///var/run/docker.sock"
                        echo "Building Green version..."
                        cd app
                        docker build -t ${ECR_REPOSITORY}:green \
                            --build-arg APP_COLOR=green .
                    '''
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', 
                                credentialsId: 'aws-credentials']]) {
                    script {
                        sh '''
                            export DOCKER_TLS_VERIFY=""
                            export DOCKER_HOST="unix:///var/run/docker.sock"
                            echo "Pushing Blue image to ECR..."
                            docker push ${ECR_REPOSITORY}:blue
                            
                            echo "Pushing Green image to ECR..."
                            docker push ${ECR_REPOSITORY}:green
                        '''
                    }
                }
            }
        }
        
        stage('Update Kubeconfig') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', 
                                credentialsId: 'aws-credentials']]) {
                    script {
                        sh '''
                            echo "Updating kubeconfig..."
                            aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_DEFAULT_REGION}
                            kubectl config current-context
                        '''
                    }
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    sh '''
                        echo "Applying Kubernetes manifests..."
                        kubectl apply -f app/blue-green/service.yaml
                        kubectl apply -f app/blue-green/blue-deployment.yaml
                        kubectl apply -f app/blue-green/green-deployment.yaml
                        kubectl apply -f app/blue-green/ingress.yaml
                        
                        echo "Waiting for deployments to be ready..."
                        kubectl rollout status deployment/nodejs-app-blue --timeout=300s
                        kubectl rollout status deployment/nodejs-app-green --timeout=300s
                        
                        echo "Current deployment status:"
                        kubectl get pods -l app=nodejs-app
                        kubectl get svc nodejs-app-service
                    '''
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    sh '''
                        echo "Performing health checks..."
                        
                        # Wait for service to get external IP
                        sleep 60
                        
                        # Get service URL
                        SERVICE_URL=$(kubectl get svc nodejs-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                        if [ -z "$SERVICE_URL" ]; then
                            echo "Warning: Service URL not available yet"
                            # Try to get ClusterIP instead
                            CLUSTER_IP=$(kubectl get svc nodejs-app-service -o jsonpath='{.spec.clusterIP}')
                            echo "Service ClusterIP: $CLUSTER_IP"
                        else
                            echo "Service URL: http://$SERVICE_URL"
                            # Optional: Add curl health check here
                            # curl -f "http://$SERVICE_URL/health" || echo "Health check failed"
                        fi
                        
                        # Verify pods are running
                        kubectl get pods -l app=nodejs-app
                        kubectl wait --for=condition=ready pod -l app=nodejs-app --timeout=300s
                    '''
                }
            }
        }
        
        stage('Traffic Switch (Optional)') {
            when {
                expression { params.SWITCH_TRAFFIC == true }
            }
            steps {
                script {
                    sh '''
                        echo "Switching traffic..."
                        chmod +x app/blue-green/switch-traffic.sh
                        ./app/blue-green/switch-traffic.sh
                    '''
                }
            }
        }
    }
    
    post {
        success {
            echo 'Blue-green deployment completed successfully!'
            script {
                sh '''
                    echo "=== Deployment Summary ==="
                    kubectl get deployments -l app=nodejs-app
                    kubectl get svc nodejs-app-service
                    echo "==========================="
                '''
            }
        }
        failure {
            echo 'Deployment failed! Check the logs above.'
        }
        always {
            sh '''
                export DOCKER_TLS_VERIFY=""
                export DOCKER_HOST="unix:///var/run/docker.sock"
                echo "Cleaning up Docker images..."
                docker image prune -f || true
            '''
        }
    }
    
    parameters {
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between blue/green deployments')
    }
}
