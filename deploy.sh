#!/bin/bash
cd terraform
terraform init
terraform apply -auto-approve

INSTANCE_IP=$(terraform output -raw instance_public_ip)
echo "EC2 Public IP: $INSTANCE_IP"

cd ..

echo " Updating Ansible inventory"
cat > ansible/inventory.ini <<EOF
[server]
$INSTANCE_IP ansible_user=ubuntu ansible_ssh_private_key_file=/home/saurabh/Downloads/Pem-files/k3s.pem
EOF

echo " Waiting for SSH to become available..."
while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "/home/saurabh/Downloads/Pem-files/k3s.pem" ubuntu@$INSTANCE_IP exit 2>/dev/null; do   
  echo "SSH not ready, retrying in 5 seconds..."
  sleep 5
done
echo " SSH connection established."

echo "Step 2: Running Ansible playbook to install K3s"
ansible-playbook -i ansible/inventory.ini ansible/install_k3s.yaml

echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

echo "Waiting for cert-manager components to be ready..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=120s

kubectl create namespace my-app || echo "Namespace 'my-app' already exists"

echo "Step 3: Deploying K8s application"
kubectl apply -f k3s-files/letsencrypt-prod.yaml
kubectl apply -f k3s-files/traefik-https-redirect-middleware.yaml
kubectl apply -f k3s-files/ecom.yaml
kubectl apply -f k3s-files/monitoring-ingress.yaml

echo "Deployment completed!"
echo " Access your app at: https://ecom.saurabhmate.cloud"
