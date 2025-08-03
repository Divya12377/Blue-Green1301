pipeline {
    agent any

    environment {
        AWS_REGION = 'us-west-2'
        ECR_REPO = '603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks'
        DOCKER_IMAGE_BLUE = "${ECR_REPO}:blue"
        DOCKER_IMAGE_GREEN = "${ECR_REPO}:green"
        KUBE_CONFIG = "$HOME/.kube/config"
        DEPLOY_YAML_DIR = 'app/blue-green'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Build & Push Docker Images') {
            steps {
                script {
                    for (def COLOR in ['blue', 'green']) {
                        sh """
                            aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO
                            docker build -t $ECR_REPO:${COLOR} ./app
                            docker push $ECR_REPO:${COLOR}
                        """
                    }
                }
            }
        }
        stage('Deploy to EKS') {
            steps {
                script {
                    // Assumes you already have the kubeconfig set up in Jenkins agent!
                    sh """
                        kubectl apply -f $DEPLOY_YAML_DIR/
                    """
                }
            }
        }
        stage('Post-Deploy: Traffic Switch (Optional)') {
            when {
                expression { return params.TRAFFIC_SWITCH == true }
            }
            steps {
                sh "bash app/blue-green/switch-traffic.sh"
            }
        }
    }
    parameters {
        booleanParam(defaultValue: false, description: 'Switch traffic blue<->green post deploy?', name: 'TRAFFIC_SWITCH')
    }
    post {
        success {
            echo 'Deployment pipeline completed successfully.'
        }
        failure {
            echo 'Deployment pipeline failed.'
        }
    }
}

