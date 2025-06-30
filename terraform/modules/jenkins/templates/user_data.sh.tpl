#!/bin/bash
set -e

# Logging setup
exec > >(tee /var/log/jenkins-install.log)
exec 2>&1

echo "==================================="
echo "Jenkins Installation Started: $(date)"
echo "Environment: ${environment}"
echo "AWS Region: ${aws_region}"
echo "==================================="

# Update system
echo "📦 Updating system packages..."
yum update -y

# Install required packages
echo "📦 Installing required packages..."
yum install -y \
    wget \
    curl \
    git \
    unzip \
    java-11-amazon-corretto \
    docker \
    jq \
    htop \
    vim

# Configure Java
echo "☕ Configuring Java environment..."
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto' >> /etc/environment
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/environment
source /etc/environment

# Install Jenkins
echo "🚀 Installing Jenkins..."
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
yum install -y jenkins

# Create Jenkins directories
mkdir -p /var/lib/jenkins/{init.groovy.d,plugins}
chown -R jenkins:jenkins /var/lib/jenkins

# Configure Jenkins
echo "⚙️ Configuring Jenkins..."
cat > /etc/sysconfig/jenkins << EOF
JENKINS_HOME="/var/lib/jenkins"
JENKINS_JAVA_CMD=""
JENKINS_USER="jenkins"
JENKINS_JAVA_OPTIONS="${jenkins_java_opts} -Djava.awt.headless=true"
JENKINS_PORT="8080"
JENKINS_LISTEN_ADDRESS=""
JENKINS_HTTPS_PORT=""
JENKINS_HTTPS_KEYSTORE=""
JENKINS_HTTPS_KEYSTORE_PASSWORD=""
JENKINS_HTTPS_LISTEN_ADDRESS=""
JENKINS_HTTP2_PORT=""
JENKINS_DEBUG_LEVEL="5"
JENKINS_ENABLE_ACCESS_LOG="no"
JENKINS_HANDLER_MAX="100"
JENKINS_HANDLER_IDLE="20"
JENKINS_EXTRA_LIB_FOLDER=""
JENKINS_ARGS=""
EOF

# Configure Docker
echo "🐳 Configuring Docker..."
systemctl enable docker
systemctl start docker
usermod -a -G docker jenkins
usermod -a -G docker ec2-user

# Install Docker Compose
echo "🐳 Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install kubectl for EKS integration
echo "☸️ Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install AWS CLI v2
echo "☁️ Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Terraform for infrastructure jobs
echo "🏗️ Installing Terraform..."
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_1.5.0_linux_amd64.zip

# Set up Jenkins admin user and configuration
echo "👤 Setting up Jenkins admin user..."
cat > /var/lib/jenkins/init.groovy.d/basic-security.groovy << 'EOF'
#!groovy
import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule

def instance = Jenkins.getInstance()

// Create admin user
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "${jenkins_admin_password}")
instance.setSecurityRealm(hudsonRealm)

// Set authorization strategy
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// Disable CLI over remoting
instance.getDescriptor("jenkins.CLI").get().setEnabled(false)

// Enable agent → master security
instance.getInjector().getInstance(AdminWhitelistRule.class).setMasterKillSwitch(false)

// Save configuration
instance.save()
EOF

# Configure Jenkins system settings
echo "⚙️ Configuring Jenkins system settings..."
cat > /var/lib/jenkins/init.groovy.d/system-config.groovy << 'EOF'
#!groovy
import jenkins.model.*
import hudson.model.*

def instance = Jenkins.getInstance()

// Set number of executors
instance.setNumExecutors(2)

// Set Jenkins URL
def jlc = JenkinsLocationConfiguration.get()
jlc.setUrl("http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080/")
jlc.save()

// Configure global tool installations
def globalConfigService = instance.getExtensionList(jenkins.model.GlobalConfiguration.class)

instance.save()
EOF

%{ if nexus_url != "" }
# Configure Jenkins to use Nexus for Maven dependencies
echo "📦 Configuring Nexus integration..."
cat > /var/lib/jenkins/init.groovy.d/nexus-config.groovy << 'EOF'
#!groovy
import jenkins.model.*
import hudson.tools.*

def instance = Jenkins.getInstance()

// Configure Maven to use Nexus proxy
def mavenInstallation = new Maven.MavenInstallation(
    "Maven-3",
    "",
    [new InstallSourceProperty([new Maven.MavenInstaller("3.9.4")])]
)

def mavenDescriptor = instance.getDescriptorByType(Maven.DescriptorImpl.class)
mavenDescriptor.setInstallations(mavenInstallation)
mavenDescriptor.save()

instance.save()
EOF

# Create Maven settings.xml for Nexus
mkdir -p /var/lib/jenkins/.m2
cat > /var/lib/jenkins/.m2/settings.xml << 'EOF'
<settings>
    <mirrors>
        <mirror>
            <id>nexus-maven-proxy</id>
            <mirrorOf>*</mirrorOf>
            <url>${nexus_url}/repository/maven-central-proxy/</url>
        </mirror>
    </mirrors>
</settings>
EOF
chown -R jenkins:jenkins /var/lib/jenkins/.m2
%{ endif }

%{ if consul_server_ips != "" }
# Install and configure Consul agent for service registration
echo "🔗 Installing Consul agent..."
CONSUL_VERSION="1.17.0"
cd /tmp
wget https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip
unzip consul_$${CONSUL_VERSION}_linux_amd64.zip
mv consul /usr/local/bin/
rm consul_$${CONSUL_VERSION}_linux_amd64.zip

# Create consul user and directories
useradd --system --home /var/lib/consul --shell /bin/false consul
mkdir -p /opt/consul /var/lib/consul /etc/consul.d
chown -R consul:consul /opt/consul /var/lib/consul /etc/consul.d

# Configure Consul agent
cat > /etc/consul.d/consul.json << EOF
{
  "datacenter": "${environment}-aws",
  "node_name": "jenkins-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
  "server": false,
  "data_dir": "/var/lib/consul",
  "log_level": "INFO",
  "retry_join": ["${consul_server_ips}"],
  "bind_addr": "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)",
  "client_addr": "127.0.0.1",
  "services": [
    {
      "name": "jenkins",
      "port": 8080,
      "tags": ["ci-cd", "automation", "build-server", "${environment}"],
      "check": {
        "http": "http://localhost:8080/login",
        "interval": "30s"
      }
    }
  ]
}
EOF

# Create Consul systemd service
cat > /etc/systemd/system/consul.service << EOF
[Unit]
Description=Consul
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.json

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Consul
systemctl daemon-reload
systemctl enable consul
systemctl start consul
%{ endif }

# Install Jenkins plugins
echo "🔌 Installing Jenkins plugins..."
cat > /var/lib/jenkins/init.groovy.d/install-plugins.groovy << 'EOF'
#!groovy
import jenkins.model.*
import java.util.logging.Logger

def logger = Logger.getLogger("")
def installed = false
def instance = Jenkins.getInstance()

def plugins = [
  "blueocean",
  "pipeline-stage-view", 
  "docker-workflow",
  "kubernetes",
  "git",
  "github",
  "github-branch-source",
  "pipeline-github-lib",
  "nodejs",
  "ant",
  "gradle", 
  "maven-invoker",
  "build-timeout",
  "timestamper",
  "ws-cleanup",
  "prometheus"
]

def pluginManager = instance.getPluginManager()
def updateCenter = instance.getUpdateCenter()

plugins.each { pluginName ->
  if (!pluginManager.getPlugin(pluginName)) {
    logger.info("Installing plugin: " + pluginName)
    def plugin = updateCenter.getPlugin(pluginName)
    if (plugin) {
      plugin.deploy(true)
      installed = true
    }
  }
}

if (installed) {
  logger.info("Plugins installed, restarting Jenkins")
  instance.restart()
}
EOF

# Configure firewall
echo "🔥 Configuring firewall..."
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --permanent --add-port=50000/tcp
firewall-cmd --permanent --add-port=22/tcp
firewall-cmd --reload

# Set proper ownership
chown -R jenkins:jenkins /var/lib/jenkins

# Start Jenkins
echo "🚀 Starting Jenkins service..."
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to start
echo "⏳ Waiting for Jenkins to start..."
timeout=300
counter=0
while [ $counter -lt $timeout ]; do
    if curl -s http://localhost:8080/login > /dev/null; then
        echo "✅ Jenkins is running!"
        break
    fi
    sleep 5
    counter=$((counter + 5))
done

if [ $counter -ge $timeout ]; then
    echo "❌ Jenkins failed to start within $timeout seconds"
    exit 1
fi

# Create a basic pipeline job for testing
echo "🔧 Creating basic pipeline job..."
cat > /var/lib/jenkins/jobs/hello-world-pipeline/config.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.40">
  <actions/>
  <description>Basic hello world pipeline for testing</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <jenkins.model.BuildDiscarderProperty>
      <strategy class="hudson.tasks.LogRotator">
        <daysToKeep>-1</daysToKeep>
        <numToKeep>10</numToKeep>
        <artifactDaysToKeep>-1</artifactDaysToKeep>
        <artifactNumToKeep>-1</artifactNumToKeep>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.92">
    <script>
pipeline {
    agent any
    stages {
        stage('Hello') {
            steps {
                echo 'Hello World from Jenkins!'
                echo "Environment: ${environment}"
                echo "Build Number: $${BUILD_NUMBER}"
                echo "Jenkins URL: $${JENKINS_URL}"
            }
        }
        stage('System Info') {
            steps {
                sh 'uname -a'
                sh 'java -version'
                sh 'docker --version'
                sh 'kubectl version --client'
            }
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

mkdir -p /var/lib/jenkins/jobs/hello-world-pipeline
chown -R jenkins:jenkins /var/lib/jenkins/jobs

# Restart Jenkins to apply all configurations
echo "🔄 Restarting Jenkins to apply configurations..."
systemctl restart jenkins

# Wait for Jenkins to restart
echo "⏳ Waiting for Jenkins to restart..."
sleep 30
timeout=300
counter=0
while [ $counter -lt $timeout ]; do
    if curl -s http://localhost:8080/login > /dev/null; then
        echo "✅ Jenkins restarted successfully!"
        break
    fi
    sleep 5
    counter=$((counter + 5))
done

# Create deployment summary
echo "📋 Creating deployment summary..."
cat > /home/ec2-user/jenkins-info.txt << EOF
Jenkins Deployment Summary
==========================
Deployment Date: $(date)
Environment: ${environment}
AWS Region: ${aws_region}

Access Information:
- Jenkins URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080
- Admin Username: admin
- Admin Password: ${jenkins_admin_password}
- SSH Access: ssh -i your-key ec2-user@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

Integration Status:
- Nexus: ${nexus_url != "" ? "Enabled" : "Disabled"}
- Consul: ${consul_server_ips != "" ? "Enabled" : "Disabled"}
- Docker: Enabled
- Kubernetes (kubectl): Enabled
- AWS CLI: Enabled
- Terraform: Enabled

Installed Plugins:
- Blue Ocean Pipeline
- Docker Workflow
- Kubernetes
- Git/GitHub Integration
- Node.js
- Maven
- Gradle
- Prometheus

Log Files:
- Installation: /var/log/jenkins-install.log
- Jenkins: /var/log/jenkins/jenkins.log
- Consul (if enabled): journalctl -u consul

Next Steps:
1. Access Jenkins at the URL above
2. Login with admin credentials
3. Run the 'hello-world-pipeline' job for testing
4. Configure additional jobs as needed
EOF

chown ec2-user:ec2-user /home/ec2-user/jenkins-info.txt

echo "==================================="
echo "✅ Jenkins Installation Complete!"
echo "📋 Summary saved to: /home/ec2-user/jenkins-info.txt"
echo "🌐 Access URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "👤 Admin User: admin"
echo "🔑 Admin Password: ${jenkins_admin_password}"
echo "==================================="

# Final status check
if systemctl is-active --quiet jenkins; then
    echo "✅ Jenkins service is running"
else
    echo "❌ Jenkins service is not running"
    systemctl status jenkins
    exit 1
fi

%{ if consul_server_ips != "" }
if systemctl is-active --quiet consul; then
    echo "✅ Consul agent is running"
else
    echo "❌ Consul agent is not running" 
    systemctl status consul
fi
%{ endif }

echo "🎉 Jenkins deployment completed successfully at $(date)" 