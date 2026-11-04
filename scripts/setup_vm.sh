#!/usr/bin/env bash
# Rebuild the Jenkins exam environment on a fresh DataScientest VM.
# Usage: bash scripts/setup_vm.sh
set -e

echo "== 1. Kubernetes access, remove ghost nodes and stuck pods =="
mkdir -p ~/.kube
if [ -f /etc/rancher/k3s/k3s.yaml ]; then
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown "$USER":"$USER" ~/.kube/config && chmod 600 ~/.kube/config
fi
kubectl get nodes --no-headers | awk '$2=="NotReady"{print $1}' | xargs -r kubectl delete node
kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
  | awk -v n="$(hostname)" '$3!=n {print $1, $2}' \
  | while read ns p; do kubectl delete pod -n "$ns" "$p" --force --grace-period=0; done

echo "== 2. Namespaces =="
for ns in dev qa staging prod; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "== 3. Helm =="
command -v helm >/dev/null 2>&1 || \
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "== 4. Java 21 + latest Jenkins LTS on port 9000 =="
sudo mkdir -p /etc/systemd/system/jenkins.service.d
printf '[Service]\nEnvironment="JENKINS_PORT=9000"\n' | sudo tee /etc/systemd/system/jenkins.service.d/port.conf >/dev/null
sudo apt-get update -qq || true
sudo apt-get install -y openjdk-21-jre-headless
sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java
sudo grep -rl pkg.jenkins.io /etc/apt/sources.list.d/ 2>/dev/null | xargs -r sudo rm -f
sudo mkdir -p /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -o Dpkg::Options::="--force-confold" jenkins

echo "== 5. Jenkins access to Docker and Kubernetes =="
sudo usermod -aG docker jenkins
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp ~/.kube/config /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
sudo systemctl daemon-reload
sudo systemctl restart jenkins
sleep 40

echo "================ SUMMARY ================"
kubectl get nodes
kubectl get ns dev qa staging prod
helm version --short
java -version 2>&1 | head -1
dpkg -l jenkins | tail -1 | awk '{print "Jenkins version:", $3}'
sudo -u jenkins -H docker ps >/dev/null 2>&1 && echo "Jenkins -> Docker: OK" || echo "Jenkins -> Docker: FAIL"
sudo -u jenkins -H kubectl get ns >/dev/null 2>&1 && echo "Jenkins -> Kubernetes: OK" || echo "Jenkins -> Kubernetes: FAIL"
sudo test -f /var/lib/jenkins/secrets/initialAdminPassword && \
  echo "Initial admin password: $(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)"
echo "Jenkins URL: http://$(curl -s ifconfig.me):9000"
