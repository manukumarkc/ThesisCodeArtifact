#!/bin/bash

# Code Artifact of Project

# Step 1: Download AWS CLI (Mac OS)
echo "Downloading AWS CLI..."
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo ln -s /folder/installed/aws-cli/aws /usr/local/bin/aws
sudo ln -s /folder/installed/aws-cli/aws_completer /usr/local/bin/aws_completer

# Step 2: Download EKSCTL Version
echo "Downloading EKSCTL..."
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
# (Optional) Verify checksum
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin

# Step 3: Install Kubernetes Kubectl version 1.30
echo "Installing Kubernetes Kubectl..."
curl -O "https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.6/2024-11-15/bin/darwin/amd64/kubectl"
# Execute permission for binary
chmod +x ./kubectl
# Export the path
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH

# Step 4: Check Version of EKSCTL and KUBECTL
echo "Checking versions..."
eksctl version
kubectl version --client

# Step 5: Deploy Nodes on the EKS cluster
echo "Deploying nodes on EKS cluster..."
eksctl create cluster --name project-cluster --region eu-west-1 --nodegroup-name standard --node-type t2.medium --nodes 2 --managed
eksctl get cluster

# Step 6: Update the EKS Configuration
echo "Updating EKS configuration..."
aws eks update-kubeconfig --name project-cluster --region eu-west-1

# Step 7: Check total nodes in Cluster
echo "Checking total nodes..."
kubectl get nodes

# Step 8: Download Istio Service Mesh
echo "Downloading Istio Service Mesh..."
curl -L "https://istio.io/downloadIstio" | sh -

# Step 9: Move into Istio Package folder
echo "Moving into Istio package folder..."
cd istio-1.24.1

# Step 10: Add istioctl client to path
echo "Adding istioctl client to path..."
export PATH=$PWD/bin:$PATH

# Step 11: Install Demo Profile to Istio without any gateways
echo "Installing Demo Profile to Istio..."
istioctl install -f samples/bookinfo/demo-profile-no-gateways.yaml -y

# Step 12: Add Default namespace to Istio Service Mesh
echo "Adding default namespace to Istio Service Mesh..."
kubectl label namespace default istio-injection=enabled

# Step 13: Install Gateway API CRD to the Cluster
echo "Installing Gateway API CRD..."
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.2.0" | kubectl apply -f -; }

# Step 14: Deploy BookInfo Application
echo "Deploying BookInfo application..."
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/release-1.24/samples/bookinfo/platform/kube/bookinfo.yaml"

# Step 15: Check Service and pods in Cluster
echo "Checking services and pods..."
kubectl get services
kubectl get pods

# Step 16: Validate if the BookInfo Application is running or not
echo "Validating BookInfo application..."
kubectl exec "$(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}')" -c ratings -- curl -sS productpage:9080/productpage | grep -o "<title>.*</title>"

# Step 17: Open the Application to Outside traffic
echo "Opening application to outside traffic..."
kubectl apply -f samples/bookinfo/gateway-api/bookinfo-gateway.yaml

# Step 18: Change the service type to ClusterIP by annotating the gateway
echo "Changing service type to ClusterIP..."
kubectl annotate gateway bookinfo-gateway networking.istio.io/service-type=ClusterIP --namespace=default

# Step 19: Check the Gateway
echo "Checking the gateway..."
kubectl get gateway

# Step 20: Access the application by Port Forwarding to 8080
echo "Accessing the application by port forwarding..."
kubectl port-forward svc/bookinfo-gateway-istio 8080:80
echo "http://localhost:8080/productpage"

# Step 21: View Dashboards
echo "Viewing dashboards..."
kubectl apply -f samples/addons
kubectl rollout status deployment/kiali -n istio-system

# Step 22: View Kiali Dashboards
echo "Viewing Kiali dashboards..."
istioctl dashboard kiali

# Step 23: View Prometheus Dashboards
echo "Viewing Prometheus dashboards..."
istioctl dashboard prometheus

# Step 24: View Grafana Dashboards
echo "Viewing Grafana dashboards..."
istioctl dashboard grafana

# Circuit Breaking the Bookinfo application

# Step 25: Deploying httpbin service
echo "Deploying httpbin service..."
kubectl apply -f samples/httpbin/httpbin.yaml

# Step 26: Configuring static circuit breaking rule with Destination rule
echo "Configuring static circuit breaking rule..."
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
spec:
  host: httpbin
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 3m
      maxEjectionPercent: 100
EOF

# Step 27: Verify the destination rule
echo "Verifying the destination rule..."
kubectl get destinationrule httpbin -o yaml

# Step 28: Deploy Fortio Service
echo "Deploying Fortio service..."
kubectl apply -f samples/httpbin/sample-client/fortio-deploy.yaml

# Step 29: Login to Fortio Service Client to Produce Load testing
echo "Logging into Fortio service client..."
export FORTIO_POD=$(kubectl get pods -l app=fortio -o 'jsonpath={.items[0].metadata.name}')
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio curl -quiet http://httpbin:8000/get

# Step 30: Trip the Service with –c 2 and 20 Requests to BookInfo application by Fortio
echo "Tripping the service with –c 2 and 20 requests..."
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 2 -qps 0 -n 20 -loglevel Warning http://httpbin:8000/get

# Step 31: Trip the Service with –c 3 and 30 Requests to BookInfo application by Fortio
echo "Tripping the service with –c 3 and 30 requests..."
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 3 -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get

# Step 32: Trip the Service with –c 4 and 40 Requests to BookInfo application by Fortio
echo "Tripping the service with –c 4 and 40 requests..."
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 4 -qps 0 -n 40 -loglevel Warning http://httpbin:8000/get

# Step 33: Check the Pending Request for every Load on Request
echo "Checking the pending request for every load..."
kubectl exec "$FORTIO_POD" -c istio-proxy -- pilot-agent request GET stats | grep httpbin | grep pending

# Step 34: Dynamic Circuit Principle for t2 Medium Node
echo "Applying dynamic circuit principle..."
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
spec:
  host: httpbin
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 2
      http:
        http1MaxPendingRequests: 2
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 1s
      baseEjectionTime: 3m
      maxEjectionPercent: 100
EOF

#Step33: Load the system by Fortio Loading –c 3 and 30 Request: 

kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 3 -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get 

#Step34: Load the system by Fortio Loading –c 4 and 40 Request: 

kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 4 -qps 0 -n 40 -loglevel Warning http://httpbin:8000/get 

#Step35: Check the Pending Request for every Load on Request: 

kubectl exec "$FORTIO_POD" -c istio-proxy -- pilot-agent request GET stats | grep httpbin | grep pending 