pipeline {
    agent any
    environment {
        ECR_REPO = "603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks"
        CLUSTER_NAME = "capgemini-eks"
        REGION = "us-west-2"
    }
    stages {
        stage('Checkout') {
            steps {
                git 'https://github.com/Divya12377/CapGemini_Assesement.git'
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    def color = env.BUILD_ID % 2 == 0 ? 'blue' : 'green'
                    sh "docker build -t ${ECR_REPO}:${color} ./app"
                }
            }
        }
        stage('Push to ECR') {
            steps {
                script {
                    def color = env.BUILD_ID % 2 == 0 ? 'blue' : 'green'
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'AWS_CREDENTIALS']]) {
                        sh "aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_REPO}"
                        sh "docker push ${ECR_REPO}:${color}"
                    }
                }
            }
        }
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    def color = env.BUILD_ID % 2 == 0 ? 'blue' : 'green'
                    sh "kubectl set image deployment/nodejs-app-${color} nodejs-app=${ECR_REPO}:${color}"
                    sh "kubectl rollout status deployment/nodejs-app-${color}"
                }
            }
        }
        stage('Switch Traffic') {
            steps {
                dir('app/blue-green') {
                    sh "chmod +x switch-traffic.sh && ./switch-traffic.sh"
                }
            }
        }
    }
    post {
        always {
            echo "Blue-green deployment completed successfully!"
        }
    }
}
