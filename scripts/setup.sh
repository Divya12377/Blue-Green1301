#!/bin/bash

# Create EKS cluster
eksctl create cluster -f eks/eks-cluster.yaml

# Configure kubectl
aws eks update-kubeconfig --name capgemini-eks --region us-west-2

# Install Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx

# Install Jenkins
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins -f eks/jenkins-values.yaml

# Get Jenkins admin password
printf "Jenkins Admin Password: "
kubectl exec --namespace default -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/chart-admin-password && echo

# Apply blue-green manifests
kubectl apply -f app/blue-green/

# Create ECR repository (if not exists)
aws ecr describe-repositories --repository-names capgemini-eks --region us-west-2 >/dev/null 2>&1 || \
aws ecr create-repository --repository-name capgemini-eks --region us-west-2

# Configure IAM for Jenkins
kubectl create clusterrolebinding jenkins --clusterrole=cluster-admin --serviceaccount=default:jenkins

# Output Jenkins URL
echo "Jenkins URL:"
kubectl get svc jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
