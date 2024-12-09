# ThesisCodeArtifact
#This is My Research Project Code Artifact
#Code Artifact of Project: Smart Circuit Management:Enhancing Kubernetes Service Mesh through Dynamic Circuit Breaking Principle.
#\\Below are the Detailed Steps in Deploying EKS Cluster And Istio Service Mesh and Circuit Breaker in the System.\\\

#Step1:Download AWS CLI(Mac OS): 

https://awscli.amazonaws.com/AWSCLIV2.pkg 

sudo ln -s /folder/installed/aws-cli/aws /usr/local/bin/aws 

sudo ln -s /folder/installed/aws-cli/aws_completer /usr/local/bin/aws_completer 

#Step2: Download EKSCTL Version: 

# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7` 

ARCH=amd64 

PLATFORM=$(uname -s)_$ARCH 

curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz" 

# (Optional) Verify checksum 

curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check 

tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz 

sudo mv /tmp/eksctl /usr/local/bin 

 

#Step 3: Install Kubernetes Kubectl version 1.30: 

curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.6/2024-11-15/bin/darwin/amd64/kubectl 

#Execute permission for binary 

chmod +x ./kubectl 

#Export the path 

mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH 

 

#Step4: Check Version of EKSCTL and KUBECTL: 

eksctl version 

Kubectl version –client 

 

#Step5: Deploy Nodes on the EKS cluster: 

eksctl create cluster --name project-cluster --region eu-west-1 --nodegroup-name standard --node-type t2.medium --nodes 2 --managed 9 eksctl get cluster 

#Step6: Update the EKS Configuration. 

aws eks update-kubeconfig --name project-cluster --region eu-west-1 

#Step7: Check total nodes in Cluster: 

kubectl get nodes 

#Step8:Download Istio Service Mesh: 

curl -L https://istio.io/downloadIstio | sh - 

#Step9: Move into Istio Package folder: 

cd istio-1.24.1 

#Step10:Add istioctl client to path 

export PATH=$PWD/bin:$PATH 

#Step11: Install Demo Profile to Istio without any gateways: 

istioctl install -f samples/bookinfo/demo-profile-no-gateways.yaml -y 

#Step12:Add Default namespace to Istio Service Mesh: 

kubectl label namespace default istio-injection=enabled 

 

#Step13:Install Gateway API CRD to the Cluster: 

kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \ 

{ kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.2.0" | kubectl apply -f -; } 

 

#Step14:Deploy BookInfo Application: 

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/bookinfo/platform/kube/bookinfo.yaml 

#Step15: Check Service and pods in Cluster: 

kubectl get services 

kubectl get pods 

 

#Step15: Validate if the BookInfo Application is running or not: 

kubectl exec "$(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}')" -c ratings -- curl -sS productpage:9080/productpage | grep -o "<title>.*</title>" 

 

#Step16: Open the Application to Outside traffic: 

kubectl apply -f samples/bookinfo/gateway-api/bookinfo-gateway.yaml 

#Step17: Change the service type to ClusterIP by annotating the gateway: 

kubectl annotate gateway bookinfo-gateway networking.istio.io/service-type=ClusterIP --namespace=default 

#Step18: Check the Gateway: 

kubectl get gateway 

#Step19:Access the application by Port Forwarding to 8080: 

kubectl port-forward svc/bookinfo-gateway-istio 8080:80 

http://localhost:8080/productpage 

#Step19: View Dashboards: 

kubectl apply -f samples/addons 

kubectl rollout status deployment/kiali -n istio-system 

 

#Step20: View Kiali Dashboards: 

istioctl dashboard kiali 

 

#Step21: View Prometheus Dashboards: 

istioctl dashboard prometheus 

 

#Step22: View Grafana Dashboards: 

istioctl dashboard grafana 

 

 #Circuit Breaking the Bookinfo application: 

#Step23:deploying httpbin service: 

kubectl apply -f samples/httpbin/httpbin.yaml 

 

#Step24:Configuring static circuit breaking rule with Destination rule : 

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

 

#Step25:Verify the destination rule: 

kubectl get destinationrule httpbin -o yaml 

#Step26: Deploy Fortio Service: 

kubectl apply -f samples/httpbin/sample-client/fortio-deploy.yaml 

#Step27:Login to Fortio Service Client to Produce Load testing: 

export FORTIO_POD=$(kubectl get pods -l app=fortio -o 'jsonpath={.items[0].metadata.name}') 

kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio curl -quiet http://httpbin:8000/get 

 

#Step28:trip the Service with –c 2 and 20 Request to BookInfo application by Fortio: 

kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 2 -qps 0 -n 20 -loglevel Warning http://httpbin:8000/get 

#Step29: trip the Service with –c 3 and 30 Request to BookInfo application by Fortio: 

 kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 3 -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get 

#Step30: trip the Service with –c 4 and 40 Request to BookInfo application by Fortio: 

kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 4 -qps 0 -n 40 -loglevel Warning http://httpbin:8000/get 

#Step31: Check the Pending Request for every Load on Request: 

kubectl exec "$FORTIO_POD" -c istio-proxy -- pilot-agent request GET stats | grep httpbin | grep pending 

#Step32: Dynamic Circuit Principle for t2 Medium Node: 

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

 

__________________________________ 

 

 

 

 

 

 

 

 
