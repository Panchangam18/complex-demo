#!/bin/bash

set -e

# Log everything
exec > >(tee /var/log/jenkins-install.log)
exec 2>&1

echo "🚀 Jenkins Installation Started: $(date)"

# Update system
yum update -y

# Install Java 11
yum install -y java-11-amazon-corretto

# Install Jenkins
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
yum install -y jenkins

# Install Docker
yum install -y docker
systemctl enable docker
systemctl start docker
usermod -a -G docker jenkins
usermod -a -G docker ec2-user

# Install Git
yum install -y git

# Start Jenkins
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to start
echo "⏳ Waiting for Jenkins to start..."
sleep 60

# The initial setup will be completed manually or via a setup script
# This creates a working Jenkins with the setup wizard that can be configured

echo "✅ Jenkins installation completed!"
echo "🌐 Access: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "👤 Complete setup wizard manually or run configuration script"
echo "🔑 Initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword)" 