#!/bin/bash
set -e

echo "🚀 Starting Blue-Green Deployment Setup..."

# -------- Build Custom Jenkins Image --------
echo "Building custom Jenkins image with Docker support..."
cd jenkins

# Create the Dockerfile if it doesn't exist
cat > Dockerfile << 'EOF'
FROM jenkins/jenkins:lts

USER root

# Install Docker CLI, AWS CLI, kubectl, and other necessary tools
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws/

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install eksctl
RUN curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp \
    && mv /tmp/eksctl /usr/local/bin

# Add jenkins user to docker group
RUN groupadd -g 999 docker && usermod -aG docker jenkins

COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

USER jenkins

# Install Jenkins plugins
RUN jenkins-plugin-cli --plugins \
    git \
    workflow-aggregator \
    docker-workflow \
    kubernetes \
    aws-credentials \
    blueocean \
    pipeline-stage-view
EOF

# Build the custom Jenkins image
docker build -t custom-jenkins:latest .

cd ..

# -------- EKS Cluster Setup ---------
if ! eksctl get cluster --name capgemini-eks --region us-west-2 >/dev/null 2>&1; then
    echo "Creating EKS cluster..."
    eksctl create cluster -f eks/eks-cluster.yaml
else
    echo "EKS cluster already exists. Skipping creation."
fi

# -------- Kubeconfig Setup ----------
aws eks update-kubeconfig --name capgemini-eks --region us-west-2
echo "Updated kubeconfig for cluster."

# -------- Ingress Controller --------
if ! kubectl get pods -n default -l app.kubernetes.io/name=ingress-nginx | grep Running >/dev/null 2>&1; then
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm install ingress-nginx ingress-nginx/ingress-nginx
else
    echo "Ingress controller already installed. Skipping."
fi

# Wait for ingress controller ready
echo "⏳ Waiting for ingress controller..."
kubectl wait --namespace default \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# -------- Jenkins Setup with Custom Image -------------
kubectl create ns jenkins 2>/dev/null || true

# Create updated Jenkins deployment with Docker support
cat > jenkins-deployment-updated.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      serviceAccountName: jenkins
      containers:
      - name: jenkins
        image: custom-jenkins:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        - containerPort: 50000
        volumeMounts:
        - name: jenkins-home
          mountPath: /var/jenkins_home
        - name: docker-sock
          mountPath: /var/run/docker.sock
        env:
        - name: JAVA_OPTS
          value: "-Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
        - name: DOCKER_HOST
          value: "unix:///var/run/docker.sock"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        securityContext:
          runAsUser: 0
      volumes:
      - name: jenkins-home
        emptyDir: {}
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
          type: Socket
---
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: jenkins
spec:
  type: LoadBalancer
  ports:
  - name: jenkins-web
    port: 8080
    targetPort: 8080
    protocol: TCP
  - name: jenkins-agent
    port: 50000
    targetPort: 50000
    protocol: TCP
  selector:
    app: jenkins
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: jenkins
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: jenkins
  namespace: jenkins
EOF

kubectl apply -f jenkins-deployment-updated.yaml

# Wait for Jenkins
echo "⏳ Waiting for Jenkins to start..."
kubectl wait --namespace jenkins \
    --for=condition=ready pod \
    --selector=app=jenkins \
    --timeout=600s

# Get Jenkins URL
JENKINS_URL="http://$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8080"
echo -e "\nJenkins URL: $JENKINS_URL"
echo "Username: admin"
echo "Password: 123!@#"

# -------- ECR Setup ----------------
if ! aws ecr describe-repositories --repository-names capgemini-eks --region us-west-2 >/dev/null 2>&1; then
    aws ecr create-repository --repository-name capgemini-eks --region us-west-2
else
    echo "ECR repository exists. Skipping creation."
fi

aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 603480426027.dkr.ecr.us-west-2.amazonaws.com

# -------- App Build/Push -----------
if [ ! -d "app" ]; then
    echo "❌ ERROR: The 'app' directory does not exist. Aborting."
    exit 1
fi

cd app

for COLOR in blue green; do
    echo "Building and pushing Docker image for: $COLOR"
    docker build -t 603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks:$COLOR \
        --build-arg APP_COLOR=$COLOR .
    docker push 603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks:$COLOR
done

cd ..

# -------- Deploy Application -------
echo "Applying Kubernetes blue-green deployment manifests..."
kubectl apply -f app/blue-green/

# -------- Final Output -------------
APP_URL="http://$(kubectl get svc nodejs-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo -e "\n✅ Deployment complete!"
echo "🌐 Application URL: $APP_URL"
echo "🔧 Jenkins URL: $JENKINS_URL"
echo ""
echo "Next steps:"
echo "1. Access Jenkins and create a new pipeline job"
echo "2. Point it to your GitHub repository"
echo "3. Use the updated Jenkinsfile provided"
echo "4. Configure AWS credentials in Jenkins if needed"
