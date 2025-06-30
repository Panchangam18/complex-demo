#!/bin/bash

# Nexus Repository Configuration Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=${ENVIRONMENT:-dev}
REGION=${REGION:-us-east-2}
NEXUS_NAMESPACE="nexus-${ENVIRONMENT}"

echo -e "${BLUE}🔧 Nexus Repository Configuration${NC}"
echo -e "${BLUE}=================================${NC}"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ kubectl not configured or cluster not accessible${NC}"
    echo -e "${YELLOW}💡 Run this command to connect to your EKS cluster:${NC}"
    echo -e "   aws eks update-kubeconfig --region ${REGION} --name ${ENVIRONMENT}-eks-${REGION}"
    exit 1
fi

# Check if Nexus pod is running
echo -e "${YELLOW}🔍 Checking Nexus deployment status...${NC}"
if ! kubectl get pods -n "${NEXUS_NAMESPACE}" -l app=nexus --field-selector=status.phase=Running | grep -q Running; then
    echo -e "${RED}❌ Nexus pod is not running yet${NC}"
    echo -e "${YELLOW}⏳ Please wait for Nexus to start, then run this script again${NC}"
    kubectl get pods -n "${NEXUS_NAMESPACE}" -l app=nexus
    exit 1
fi

echo -e "${GREEN}✅ Nexus is running${NC}"

# Get Nexus URL and admin password
NEXUS_SERVICE=$(kubectl get svc -n "${NEXUS_NAMESPACE}" -l app=nexus -o jsonpath='{.items[0].metadata.name}')
NEXUS_PORT=$(kubectl get svc -n "${NEXUS_NAMESPACE}" "${NEXUS_SERVICE}" -o jsonpath='{.spec.ports[0].port}')

# For LoadBalancer service, get external URL
if kubectl get svc -n "${NEXUS_NAMESPACE}" "${NEXUS_SERVICE}" -o jsonpath='{.spec.type}' | grep -q LoadBalancer; then
    echo -e "${YELLOW}⏳ Waiting for LoadBalancer external IP...${NC}"
    EXTERNAL_IP=""
    while [ -z "$EXTERNAL_IP" ]; do
        EXTERNAL_IP=$(kubectl get svc -n "${NEXUS_NAMESPACE}" "${NEXUS_SERVICE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if [ -z "$EXTERNAL_IP" ]; then
            EXTERNAL_IP=$(kubectl get svc -n "${NEXUS_NAMESPACE}" "${NEXUS_SERVICE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        fi
        if [ -z "$EXTERNAL_IP" ]; then
            echo -e "${YELLOW}⏳ LoadBalancer IP not ready yet, waiting...${NC}"
            sleep 10
        fi
    done
    NEXUS_URL="http://${EXTERNAL_IP}:${NEXUS_PORT}"
else
    # For ClusterIP/NodePort, use port-forward
    echo -e "${YELLOW}🔀 Setting up port-forward for Nexus access...${NC}"
    kubectl port-forward -n "${NEXUS_NAMESPACE}" "svc/${NEXUS_SERVICE}" 8081:${NEXUS_PORT} &
    PORT_FORWARD_PID=$!
    sleep 5
    NEXUS_URL="http://localhost:8081"
fi

echo -e "${GREEN}🌐 Nexus URL: ${NEXUS_URL}${NC}"

# Get admin password
echo -e "${YELLOW}🔑 Retrieving Nexus admin password...${NC}"
ADMIN_PASSWORD=""
MAX_RETRIES=30
RETRY_COUNT=0

while [ -z "$ADMIN_PASSWORD" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    ADMIN_PASSWORD=$(kubectl exec -n "${NEXUS_NAMESPACE}" -it $(kubectl get pods -n "${NEXUS_NAMESPACE}" -l app=nexus -o jsonpath='{.items[0].metadata.name}') -- cat /nexus-data/admin.password 2>/dev/null | tr -d '\r\n' || echo "")
    
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo -e "${YELLOW}⏳ Admin password not ready yet, waiting... (${RETRY_COUNT}/${MAX_RETRIES})${NC}"
        sleep 10
        ((RETRY_COUNT++))
    fi
done

if [ -z "$ADMIN_PASSWORD" ]; then
    echo -e "${RED}❌ Failed to retrieve admin password after ${MAX_RETRIES} attempts${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Admin password retrieved${NC}"

# Function to make API calls to Nexus
nexus_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    if [ -n "$data" ]; then
        curl -s -u "admin:${ADMIN_PASSWORD}" \
             -H "Content-Type: application/json" \
             -X "${method}" \
             -d "${data}" \
             "${NEXUS_URL}/service/rest${endpoint}"
    else
        curl -s -u "admin:${ADMIN_PASSWORD}" \
             -X "${method}" \
             "${NEXUS_URL}/service/rest${endpoint}"
    fi
}

# Wait for Nexus to be fully ready
echo -e "${YELLOW}⏳ Waiting for Nexus to be fully ready...${NC}"
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -s -f "${NEXUS_URL}/service/rest/v1/status" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Nexus is ready${NC}"
        break
    fi
    echo -e "${YELLOW}⏳ Nexus not ready yet, waiting... (${WAIT_COUNT}/${MAX_WAIT})${NC}"
    sleep 10
    ((WAIT_COUNT++))
done

if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
    echo -e "${RED}❌ Nexus did not become ready in time${NC}"
    exit 1
fi

# Create repositories
echo -e "${YELLOW}📦 Creating NPM repositories...${NC}"

# NPM Proxy Repository
nexus_api "POST" "/v1/repositories/npm/proxy" '{
  "name": "npm-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://registry.npmjs.org",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true,
    "connection": {
      "retries": 0,
      "userAgentSuffix": "string",
      "timeout": 60,
      "enableCircularRedirects": false,
      "enableCookies": false,
      "useTrustStore": false
    }
  }
}'

# NPM Hosted Repository
nexus_api "POST" "/v1/repositories/npm/hosted" '{
  "name": "npm-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow_once"
  },
  "cleanup": {
    "policyNames": ["string"]
  }
}'

# NPM Group Repository
nexus_api "POST" "/v1/repositories/npm/group" '{
  "name": "npm-public",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["npm-hosted", "npm-proxy"]
  }
}'

echo -e "${YELLOW}📦 Creating Docker repositories...${NC}"

# Docker Proxy Repository
nexus_api "POST" "/v1/repositories/docker/proxy" '{
  "name": "docker-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://registry-1.docker.io",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true,
    "connection": {
      "retries": 0,
      "userAgentSuffix": "string",
      "timeout": 60,
      "enableCircularRedirects": false,
      "enableCookies": false,
      "useTrustStore": false
    }
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": 8082,
    "httpsPort": 8083
  },
  "dockerProxy": {
    "indexType": "HUB",
    "indexUrl": "https://index.docker.io/"
  }
}'

# Docker Hosted Repository
nexus_api "POST" "/v1/repositories/docker/hosted" '{
  "name": "docker-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow_once"
  },
  "cleanup": {
    "policyNames": ["string"]
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": 8084,
    "httpsPort": 8085
  }
}'

# Docker Group Repository
nexus_api "POST" "/v1/repositories/docker/group" '{
  "name": "docker-public",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["docker-hosted", "docker-proxy"]
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": 8086,
    "httpsPort": 8087
  }
}'

echo -e "${YELLOW}📦 Creating Python (PyPI) repositories...${NC}"

# PyPI Proxy Repository
nexus_api "POST" "/v1/repositories/pypi/proxy" '{
  "name": "pypi-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://pypi.org",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true,
    "connection": {
      "retries": 0,
      "userAgentSuffix": "string",
      "timeout": 60,
      "enableCircularRedirects": false,
      "enableCookies": false,
      "useTrustStore": false
    }
  }
}'

# PyPI Group Repository
nexus_api "POST" "/v1/repositories/pypi/group" '{
  "name": "pypi-public",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["pypi-proxy"]
  }
}'

# Clean up port-forward if we started it
if [ -n "$PORT_FORWARD_PID" ]; then
    kill $PORT_FORWARD_PID 2>/dev/null || true
fi

echo -e "\n${GREEN}🎉 Nexus Configuration Complete!${NC}"
echo -e "${GREEN}=================================${NC}"
echo -e "\n${YELLOW}📋 Access Information:${NC}"
echo -e "  🌐 Nexus URL: ${NEXUS_URL}"
echo -e "  👤 Username: admin"
echo -e "  🔑 Password: ${ADMIN_PASSWORD}"
echo -e "\n${YELLOW}📦 Repository URLs:${NC}"
echo -e "  📄 NPM Registry: ${NEXUS_URL}/repository/npm-public/"
echo -e "  🐳 Docker Registry: ${EXTERNAL_IP:-localhost}:8086"
echo -e "  🐍 PyPI Index: ${NEXUS_URL}/repository/pypi-public/simple/"
echo -e "\n${YELLOW}🔧 Next Steps:${NC}"
echo -e "  1. Update your build scripts to use Nexus registries"
echo -e "  2. Configure npm: npm config set registry ${NEXUS_URL}/repository/npm-public/"
echo -e "  3. Configure pip: pip config --global set global.index-url ${NEXUS_URL}/repository/pypi-public/simple/"
echo -e "  4. Login to Docker registry: docker login ${EXTERNAL_IP:-localhost}:8086"
echo -e "\n${GREEN}✅ Your artifact management is now ready!${NC}" 