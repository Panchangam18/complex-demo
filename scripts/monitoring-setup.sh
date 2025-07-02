#!/bin/bash

# Monitoring Stack Setup for Multi-Cloud DevOps Platform
# Connects CI/CD pipeline metrics, Consul service mesh, and infrastructure monitoring

set -e

echo "🎛️ Setting up comprehensive monitoring stack..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

GRAFANA_URL="http://aac5c2cd5848e492597d2271712cdf59-852252311.us-east-2.elb.amazonaws.com"
PROMETHEUS_URL="http://a5ac996146e3f4380b9de5ed9936917b-362180694.us-east-2.elb.amazonaws.com:9090"
CONSUL_URL="http://dev-consul-ui-1506138623.us-east-2.elb.amazonaws.com"

echo -e "${BLUE}📊 Your Monitoring Stack URLs:${NC}"
echo "  Grafana:    $GRAFANA_URL"
echo "  Prometheus: $PROMETHEUS_URL" 
echo "  Consul:     $CONSUL_URL"
echo ""

# Test connectivity
echo -e "${YELLOW}🔍 Testing connectivity...${NC}"

if curl -s --connect-timeout 5 "$GRAFANA_URL" > /dev/null; then
    echo -e "${GREEN}✅ Grafana accessible${NC}"
else
    echo "❌ Grafana not accessible"
fi

if curl -s --connect-timeout 5 "$PROMETHEUS_URL/api/v1/status/config" > /dev/null; then
    echo -e "${GREEN}✅ Prometheus accessible${NC}"
else
    echo "❌ Prometheus not accessible"
fi

if curl -s --connect-timeout 5 "$CONSUL_URL/v1/status/leader" > /dev/null; then
    echo -e "${GREEN}✅ Consul accessible${NC}"
else
    echo "❌ Consul not accessible"
fi

echo ""
echo -e "${BLUE}🎯 Key Metrics to Monitor:${NC}"

# Check current metrics availability
echo -e "${YELLOW}📈 Current Prometheus targets:${NC}"
curl -s "$PROMETHEUS_URL/api/v1/targets" | jq -r '.data.activeTargets[] | "  \(.job): \(.health) - \(.scrapeUrl)"' 2>/dev/null || echo "  Use Prometheus UI to view targets"

echo ""
echo -e "${YELLOW}🔍 Available metrics preview:${NC}"
echo "  📊 Container metrics: container_cpu_usage_seconds_total"
echo "  🖥️  Node metrics: node_cpu_seconds_total"
echo "  ☸️  Kubernetes metrics: kube_pod_status_phase"
echo "  🌐 Consul metrics: consul_health_node_status"

echo ""
echo -e "${BLUE}🎛️ Grafana Dashboard Access:${NC}"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo -e "${YELLOW}📋 Pre-installed dashboards to explore:${NC}"
echo "  • Kubernetes Cluster Monitoring"
echo "  • Node Exporter Full"
echo "  • Prometheus Stats"
echo "  • AlertManager"

echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. 🌐 Open Grafana: $GRAFANA_URL"
echo "2. 🔑 Login with admin/admin123"
echo "3. 📊 Explore existing dashboards"
echo "4. 🔧 Create custom CI/CD pipeline dashboard"
echo "5. 🎯 Set up Consul service mesh monitoring"

echo ""
echo -e "${GREEN}✨ Monitoring stack is ready! Start exploring your infrastructure insights.${NC}" 