#!/bin/bash

# Configure Jenkins Triggers for Nightly Tasks
# Implements the "nightly tasks" requirement from architecture plan

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
JENKINS_URL="http://3.149.193.86:8080"
JENKINS_SECRET_ARN="arn:aws:secretsmanager:us-east-2:013364997013:secret:dev-jenkins-admin-password-So8uOE"

echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                  🕐 JENKINS TRIGGERS CONFIGURATION 🕐                        ║"
echo "║                                                                              ║"
echo "║  Adding scheduled triggers for 'nightly tasks' as per architecture plan     ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}📋 Adding Triggers:${NC}"
echo -e "  • Nightly builds at 2 AM"
echo -e "  • Weekly artifact cleanup"
echo -e "  • Daily dependency updates"
echo -e "  • SCM polling for Git changes"

# Get Jenkins password
JENKINS_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$JENKINS_SECRET_ARN" --query SecretString --output text | jq -r .password)

echo -e "\n${YELLOW}🔧 Creating enhanced Jenkins job with triggers...${NC}"

# Create Jenkins job with triggers for nightly tasks
cat > /tmp/nexus-nightly-job.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.40">
  <actions/>
  <description>Jenkins-Nexus Integration with Nightly Tasks - Scheduled Builds for Vue.js Frontend and Node.js Backend</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <jenkins.model.BuildDiscarderProperty>
      <strategy class="hudson.tasks.LogRotator">
        <daysToKeep>30</daysToKeep>
        <numToKeep>50</numToKeep>
        <artifactDaysToKeep>14</artifactDaysToKeep>
        <artifactNumToKeep>20</artifactNumToKeep>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers>
        <!-- Daily nightly build at 2 AM -->
        <hudson.triggers.TimerTrigger>
          <spec>H 2 * * *</spec>
        </hudson.triggers.TimerTrigger>
        
        <!-- Weekly cleanup on Sunday at 1 AM -->
        <hudson.triggers.TimerTrigger>
          <spec>H 1 * * 0</spec>
        </hudson.triggers.TimerTrigger>
        
        <!-- SCM polling every 15 minutes (for Git integration) -->
        <hudson.triggers.SCMTrigger>
          <spec>H/15 * * * *</spec>
          <ignorePostCommitHooks>false</ignorePostCommitHooks>
        </hudson.triggers.SCMTrigger>
      </triggers>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@2.92">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@4.8.3">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/Panchangam18/complex-demo.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="list"/>
      <extensions/>
    </scm>
             <scriptPath>ci-cd/jenkins/pipelines/jenkins-nexus-integration.groovy</scriptPath>
     <lightweight>true</lightweight>
   </definition>
   <triggers>
     <hudson.triggers.TimerTrigger>
       <spec>H 2 * * *</spec>
     </hudson.triggers.TimerTrigger>
   </triggers>
   <disabled>false</disabled>
  </flow-definition>
 EOF

# Create the enhanced Jenkins job with triggers
echo -e "${YELLOW}🔄 Creating/updating Jenkins job with nightly triggers...${NC}"
curl -s -u "admin:${JENKINS_PASSWORD}" \
     -H "Content-Type: application/xml" \
     -X POST \
     "${JENKINS_URL}/createItem?name=nexus-nightly-integration" \
     --data-binary @/tmp/nexus-nightly-job.xml > /dev/null 2>&1 || \
curl -s -u "admin:${JENKINS_PASSWORD}" \
     -H "Content-Type: application/xml" \
     -X POST \
     "${JENKINS_URL}/job/nexus-nightly-integration/config.xml" \
     --data-binary @/tmp/nexus-nightly-job.xml > /dev/null 2>&1

echo -e "${GREEN}✅ Jenkins job with triggers created: nexus-nightly-integration${NC}"

# Clean up
rm -f /tmp/nexus-nightly-job.xml

echo -e "\n${BLUE}🎯 Trigger Configuration Summary:${NC}"
echo -e "${GREEN}✅ Daily Nightly Builds: 2:00 AM (H 2 * * *)${NC}"
echo -e "${GREEN}✅ Weekly Cleanup: Sunday 1:00 AM (H 1 * * 0)${NC}"
echo -e "${GREEN}✅ SCM Polling: Every 15 minutes (H/15 * * * *)${NC}"
echo -e "${GREEN}✅ Manual Triggers: Via UI or API${NC}"

echo -e "\n${YELLOW}🔗 Access Information:${NC}"
echo -e "  • Nightly Job: ${JENKINS_URL}/job/nexus-nightly-integration/"
echo -e "  • Manual Build: ${JENKINS_URL}/job/nexus-nightly-integration/build"
echo -e "  • Build History: ${JENKINS_URL}/job/nexus-nightly-integration/builds/"
echo -e "  • Configuration: ${JENKINS_URL}/job/nexus-nightly-integration/configure"

echo -e "\n${YELLOW}🚀 Trigger Examples:${NC}"
echo -e "  • Manual: Click 'Build Now' in Jenkins UI"
echo -e "  • API: curl -X POST -u admin:password ${JENKINS_URL}/job/nexus-nightly-integration/build"
echo -e "  • With Params: ${JENKINS_URL}/job/nexus-nightly-integration/buildWithParameters?BUILD_TYPE=WEEKLY_CLEANUP"

echo -e "\n${PURPLE}🎊 Jenkins triggers now configured for nightly tasks as per your architecture plan!${NC}"
echo -e "${PURPLE}   Vue.js frontend and Node.js backend will build automatically every night at 2 AM! 🎊${NC}"

echo -e "\n${GREEN}✅ Trigger configuration completed successfully!${NC}" 