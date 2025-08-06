pipeline {
    agent any
    
    environment {
        // Docker configuration
        DOCKER_HOST = 'unix:///var/run/docker.sock'
        DOCKER_TLS_VERIFY = ''
        
        // AWS and application configuration
        AWS_DEFAULT_REGION = 'us-west-2'
        ECR_REPOSITORY = '603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks'
        CLUSTER_NAME = 'capgemini-eks'
    }
    
    stages {
        stage('Docker Setup & Verification') {
            steps {
                script {
                    sh '''
                        echo "=== Docker Setup & Verification ==="
                        echo "Current user: $(whoami)"
                        echo "User groups: $(groups)"
                        
                        # Verify Docker socket exists
                        echo "Checking Docker socket..."
                        if [ -S "/var/run/docker.sock" ]; then
                            echo "✅ Docker socket exists"
                            ls -l /var/run/docker.sock
                        else
                            echo "❌ Docker socket not found!"
                            echo "Troubleshooting:"
                            echo "1. Check host Docker: ls -l /var/run/docker.sock"
                            echo "2. Verify container mount: docker inspect ${HOSTNAME} | grep docker.sock"
                            exit 1
                        fi
                        
                        # Test Docker connection
                        echo "Testing Docker connection..."
                        docker info || { echo "❌ Docker connection failed"; exit 1; }
                        echo "✅ Docker connection successful"
                    '''
                }
            }
        }

        stage('Checkout') {
            steps {
                git branch: 'main', 
                    url: 'https://github.com/Divya12377/Blue-Green1301.git'
            }
        }
        
        stage('Verify Environment') {
            steps {
                script {
                    sh '''
                        export DOCKER_HOST="unix:///var/run/docker.sock"
                        unset DOCKER_TLS_VERIFY
                        
                        echo "Checking Docker installation..."
                        docker --version || { echo "❌ Docker not found!"; exit 1; }
                        
                        echo "Checking AWS CLI..."
                        aws --version || { echo "❌ AWS CLI not found!"; exit 1; }
                        
                        echo "Checking kubectl..."
                        kubectl version --client || { echo "❌ kubectl not found!"; exit 1; }
                        
                        echo "Verifying workspace contents..."
                        ls -la
                        ls -la app/ || { echo "❌ App directory not found!"; exit 1; }
                        
                        echo "✅ All environment dependencies verified"
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
                            export DOCKER_HOST="unix:///var/run/docker.sock"
                            unset DOCKER_TLS_VERIFY
                            
                            echo "Logging into AWS ECR..."
                            aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
                                docker login --username AWS --password-stdin ${ECR_REPOSITORY} || \
                                { echo "❌ ECR login failed"; exit 1; }
                                
                            echo "✅ Successfully logged into ECR"
                        '''
                    }
                }
            }
        }
        
        stage('Build Docker Images') {
            steps {
                script {
                    sh '''
                        export DOCKER_HOST="unix:///var/run/docker.sock"
                        unset DOCKER_TLS_VERIFY
                        
                        echo "Building Blue version..."
                        docker build -t ${ECR_REPOSITORY}:blue \
                            --build-arg APP_COLOR=blue \
                            -f app/Dockerfile app/ || \
                            { echo "❌ Blue build failed"; exit 1; }
                            
                        echo "Building Green version..."
                        docker build -t ${ECR_REPOSITORY}:green \
                            --build-arg APP_COLOR=green \
                            -f app/Dockerfile app/ || \
                            { echo "❌ Green build failed"; exit 1; }
                            
                        echo "✅ Images built successfully"
                        docker images | grep ${ECR_REPOSITORY}
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
                            export DOCKER_HOST="unix:///var/run/docker.sock"
                            unset DOCKER_TLS_VERIFY
                            
                            echo "Pushing Blue image to ECR..."
                            docker push ${ECR_REPOSITORY}:blue || \
                                { echo "❌ Blue push failed"; exit 1; }
                            
                            echo "Pushing Green image to ECR..."
                            docker push ${ECR_REPOSITORY}:green || \
                                { echo "❌ Green push failed"; exit 1; }
                                
                            echo "✅ Images pushed successfully"
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
                            aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_DEFAULT_REGION} || \
                                { echo "❌ kubeconfig update failed"; exit 1; }
                                
                            echo "Current context:"
                            kubectl config current-context
                            echo "✅ kubeconfig updated"
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
                        kubectl apply -f app/blue-green/service.yaml || \
                            { echo "❌ Service apply failed"; exit 1; }
                        kubectl apply -f app/blue-green/blue-deployment.yaml || \
                            { echo "❌ Blue deployment apply failed"; exit 1; }
                        kubectl apply -f app/blue-green/green-deployment.yaml || \
                            { echo "❌ Green deployment apply failed"; exit 1; }
                        kubectl apply -f app/blue-green/ingress.yaml || \
                            { echo "❌ Ingress apply failed"; exit 1; }
                        
                        echo "Waiting for deployments to be ready..."
                        kubectl rollout status deployment/nodejs-app-blue --timeout=5m || \
                            { echo "❌ Blue rollout failed"; exit 1; }
                        kubectl rollout status deployment/nodejs-app-green --timeout=5m || \
                            { echo "❌ Green rollout failed"; exit 1; }
                        
                        echo "✅ Deployments ready"
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
                        echo "Waiting for service to stabilize..."
                        sleep 60
                        
                        # Get service URL
                        SERVICE_URL=$(kubectl get svc nodejs-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                        if [ -z "$SERVICE_URL" ]; then
                            echo "⚠️ Service URL not available yet"
                            # Try to get ClusterIP instead
                            CLUSTER_IP=$(kubectl get svc nodejs-app-service -o jsonpath='{.spec.clusterIP}')
                            echo "Service ClusterIP: $CLUSTER_IP"
                        else
                            echo "✅ Service URL: http://$SERVICE_URL"
                            echo "Performing health check..."
                            curl -f "http://$SERVICE_URL" || \
                                { echo "❌ Health check failed"; exit 1; }
                        fi
                        
                        # Verify pods are running
                        echo "Verifying pod status..."
                        kubectl wait --for=condition=ready pod -l app=nodejs-app --timeout=5m || \
                            { echo "❌ Pods not ready"; exit 1; }
                            
                        echo "✅ All pods ready"
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
                        if [ -f "app/blue-green/switch-traffic.sh" ]; then
                            chmod +x app/blue-green/switch-traffic.sh
                            ./app/blue-green/switch-traffic.sh || \
                                { echo "❌ Traffic switch failed"; exit 1; }
                        else
                            echo "⚠️ Traffic switch script not found"
                        fi
                    '''
                }
            }
        }
    }
    
    post {
        success {
            echo '🎉 Blue-green deployment completed successfully!'
            script {
                sh '''
                    echo "=== Deployment Summary ==="
                    kubectl get deployments -l app=nodejs-app
                    kubectl get svc nodejs-app-service
                    kubectl get ingress
                    echo "==========================="
                '''
            }
        }
        failure {
            echo '❌ Deployment failed! Check the logs above.'
            script {
                sh '''
                    echo "=== FAILURE DEBUGGING ==="
                    echo "Docker info:"
                    docker info || true
                    echo "Kubernetes pods:"
                    kubectl get pods -o wide || true
                    echo "Kubernetes events:"
                    kubectl get events --sort-by='.metadata.creationTimestamp' || true
                    echo "=========================="
                '''
            }
        }
        always {
            sh '''
                export DOCKER_HOST="unix:///var/run/docker.sock"
                unset DOCKER_TLS_VERIFY
                
                echo "Cleaning up Docker images..."
                docker image prune -f || true
            '''
        }
    }
    
    parameters {
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between blue/green deployments')
    }
}
