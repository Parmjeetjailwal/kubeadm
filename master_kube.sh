#!/bin/bash
# improved-master.sh
# Script to configure a Kubernetes master node using kubeadm
# Run as root (sudo -i)

# 1) Disable swap & add kernel settings
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2) Add kernel settings & Enable IP tables (CNI Prerequisites)
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# 3) Install containerd runtime
apt-get update -y
apt-get install ca-certificates curl gnupg lsb-release -y

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install containerd
apt-get update -y
apt-get install containerd.io -y

# Generate default configuration file for containerd
containerd config default > /etc/containerd/config.toml

# Configure cgroup as systemd for containerd
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Restart and enable containerd service
systemctl restart containerd
systemctl enable containerd

# 4) Install Kubernetes components (updated for newer Ubuntu)
# Update the apt package index and install packages needed
apt-get update
apt-get install -y apt-transport-https ca-certificates curl

# Download the Google Cloud public signing key (newer method)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes apt repository (updated URL)
# This uses the newer repository structure based on your Ubuntu version
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Update apt package index, install kubelet, kubeadm and kubectl
apt-get update
# If you want a specific version, you can specify it with the = sign (e.g., kubelet=1.28.0-00)
apt-get install -y kubelet kubeadm kubectl

# Pin their version to prevent automatic upgrades
apt-mark hold kubelet kubeadm kubectl

# Enable and start kubelet service
systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet.service

# 5) Initialize Kubernetes master node with kubeadm
echo "Initializing Kubernetes control plane..."
kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubectl configuration for the root user
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Apply Weave network plugin
echo "Deploying Weave Net as the CNI solution..."
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

# Generate a join command for worker nodes
echo "Generating token for worker nodes to join..."
kubeadm token create --print-join-command

echo "Master node setup complete!"
