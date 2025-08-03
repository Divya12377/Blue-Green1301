#!/bin/bash
set -e

echo "🚀 Starting Blue-Green Deployment Setup..."

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

# -------- Jenkins Setup -------------
kubectl create ns jenkins 2>/dev/null || true
kubectl apply -f jenkins/jenkins-deployment.yaml

# Wait for Jenkins
echo "⏳ Waiting for Jenkins to start..."
kubectl wait --namespace jenkins \
    --for=condition=ready pod \
    --selector=app=jenkins \
    --timeout=300s

# Get Jenkins credentials
JENKINS_URL="http://$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
JENKINS_PASS="$(kubectl exec -n jenkins deployment/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword)"
echo -e "\nJenkins URL: $JENKINS_URL"
echo "Admin password: $JENKINS_PASS"

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

if [ ! -f "app/package.json" ]; then
    echo "❌ ERROR: The 'app/package.json' file does not exist! Aborting."
    exit 1
fi

cd app

for COLOR in blue green; do
    echo "Building and pushing Docker image for: $COLOR"
    docker build -t 603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks:$COLOR .
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

