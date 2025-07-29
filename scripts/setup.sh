#!/bin/bash

# Create EKS cluster
if ! eksctl get cluster --name capgemini-eks --region us-west-2 >/dev/null 2>&1; then
    echo "Creating EKS cluster..."
    eksctl create cluster -f eks/eks-cluster.yaml
else
    echo "EKS cluster already exists. Skipping creation."
fi

# Configure kubectl
aws eks update-kubeconfig --name capgemini-eks --region us-west-2

# Install Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx

# Wait for ingress controller
echo "Waiting for ingress controller..."
kubectl wait --namespace default \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# Setup Jenkins
kubectl create ns jenkins 2>/dev/null || true
kubectl apply -f jenkins/jenkins-deployment.yaml

# Wait for Jenkins
echo "Waiting for Jenkins to start..."
kubectl wait --namespace jenkins \
  --for=condition=ready pod \
  --selector=app=jenkins \
  --timeout=300s

# Get Jenkins credentials
echo -e "\nJenkins URL: http://$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "Admin password: $(kubectl exec -n jenkins deployment/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword)"

# Create ECR repository
aws ecr describe-repositories --repository-names capgemini-eks --region us-west-2 >/dev/null 2>&1 || \
aws ecr create-repository --repository-name capgemini-eks --region us-west-2

# Build and push initial images
cd app
for COLOR in blue green; do
  docker build -t 603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks:$COLOR .
  docker push 603480426027.dkr.ecr.us-west-2.amazonaws.com/capgemini-eks:$COLOR
done
cd ..

# Deploy application
kubectl apply -f app/blue-green/

# Print final status
echo -e "\nDeployment complete!"
echo "Application URL: http://$(kubectl get svc nodejs-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
