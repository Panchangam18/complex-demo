# Load Testing Guide

This directory contains comprehensive load testing configurations using [Artillery.io](https://artillery.io/) for testing the multi-cloud infrastructure.

## 🎯 **Overview**

The load testing setup is designed to:
- **Test existing deployed infrastructure** (not spin up new infrastructure)
- **Dynamically retrieve URLs** from the current Kubernetes deployment
- **Support multiple environments** (dev, staging, prod)
- **Provide realistic load testing scenarios**

## 📁 **Directory Structure**

```
Code/
├── client/src/tests/stresstests/      # Frontend load tests
│   ├── stress_client.yml              # Basic frontend load test
│   └── stress_client_realistic.yml    # Realistic user journey simulation
├── server/src/tests/stresstests/      # Backend load tests
│   ├── stress_server.yml              # Basic backend load test
│   ├── stress_server_intensive.yml    # Intensive multi-phase load test
│   └── stress_server_template.yml     # Template with environment variables
└── tests/
    └── README.md                      # This file
```

## 🚀 **Quick Start**

### **1. Update URLs for Current Environment**
```bash
# Update Artillery configs with current deployment URLs
./scripts/update-load-test-urls.sh

# Or specify environment explicitly
./scripts/update-load-test-urls.sh -e dev -r us-east-2
```

### **2. Run Load Tests**
```bash
# Install Artillery (if not already installed)
npm install -g artillery

# Run comprehensive load tests
make run-load-tests

# Or run specific tests
make run-backend-load-test
make run-frontend-load-test
make run-quick-load-test
```

## 📊 **Load Test Configurations**

### **Backend Load Tests**

#### `stress_server_intensive.yml` - Multi-Phase Load Test
- **Warm-up**: 5 users for 30s
- **Ramp-up**: 10→50 users over 60s  
- **Sustained**: 50 users for 120s
- **Spike**: 100 users for 30s
- **Cool-down**: 50→5 users over 60s

#### `stress_server.yml` - Basic Load Test
- **Duration**: 100s
- **Concurrent Users**: 20
- **Timeout**: 5s
- **Connection Pool**: 50

### **Frontend Load Tests**

#### `stress_client_realistic.yml` - Business Hours Simulation
- **Morning Ramp-up**: 1→30 users over 5 minutes
- **Peak Hours**: 30 users for 10 minutes
- **Evening Wind-down**: 30→5 users over 5 minutes
- **User Behaviors**: Landing page, browsing, engagement simulation

#### `stress_client.yml` - Basic Frontend Test
- **Duration**: 100s
- **Concurrent Users**: 20
- **Target**: Frontend load balancer

## 🔧 **Dynamic URL Configuration**

### **How It Works**

1. **Kubernetes Services**: Applications are deployed with `LoadBalancer` services
   ```yaml
   # Frontend and Backend services create AWS NLBs
   spec:
     type: LoadBalancer
     annotations:
       service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
   ```

2. **URL Retrieval**: Script gets load balancer URLs dynamically
   ```bash
   # Get frontend URL
   kubectl get svc frontend-service -n frontend-dev \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   
   # Get backend URL  
   kubectl get svc backend-service -n backend-dev \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

3. **Config Update**: Artillery YAML files are updated with current URLs
   ```yaml
   # Before: Hardcoded URL
   config:
     target: "http://alb-a37-demo-ser-1441792879.us-east-1.elb.amazonaws.com"
   
   # After: Dynamic URL from current deployment
   config:
     target: "http://your-current-backend-nlb-url.elb.us-east-2.amazonaws.com"
   ```

### **Manual URL Update**
```bash
# Get current URLs manually
kubectl get svc -A | grep LoadBalancer

# Update specific Artillery config
./scripts/update-load-test-urls.sh --env prod --region us-west-2
```

## 🌐 **Environment Support**

The load testing setup supports multiple environments with different configurations:

### **Development Environment**
```bash
./scripts/update-load-test-urls.sh -e dev -r us-east-2
```

### **Staging Environment**
```bash
./scripts/update-load-test-urls.sh -e staging -r us-west-2
```

### **Production Environment**
```bash
./scripts/update-load-test-urls.sh -e prod -r us-west-2
```

## 📈 **Load Test Scenarios**

### **Backend API Testing**
- **GET /api/getAllProducts** - Product catalog load testing
- **GET /status** - Health check endpoint testing
- **Response validation** - Status code and JSON structure verification
- **Timeout handling** - 10-second request timeout

### **Frontend Testing**
- **Landing page load** - Homepage performance
- **User journey simulation** - Multi-step user interactions
- **Think time modeling** - Realistic user behavior
- **Bounce rate testing** - Quick visitor patterns

## 🔍 **Monitoring Integration**

Load tests integrate with your observability stack:

### **DataDog Integration**
```bash
# DataDog automatically captures load test metrics
# View in DataDog dashboard: Infrastructure → Load Balancers
```

### **Prometheus/Grafana**
```bash
# Artillery can push metrics to Prometheus
export PROMETHEUS_PUSHGATEWAY_URL="http://prometheus-pushgateway:9091"
```

### **CloudWatch Metrics**
```bash
# AWS load balancer metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name RequestCount
```

## 🎯 **Advanced Usage**

### **Custom Load Test Scenarios**
```bash
# Use template for custom scenarios
cp Code/server/src/tests/stresstests/stress_server_template.yml my_custom_test.yml

# Edit configuration
vim my_custom_test.yml

# Run custom test
artillery run my_custom_test.yml
```

### **Environment Variables**
```bash
# Set custom parameters
export SUSTAINED_RATE=75
export SPIKE_RATE=150
export HTTP_TIMEOUT=15

# Run with custom parameters
artillery run stress_server_intensive.yml
```

### **Load Test Reporting**
```bash
# Generate detailed report
artillery run --output report.json stress_server_intensive.yml
artillery report report.json

# View HTML report
open report.json.html
```

## 🚨 **Important Notes**

1. **Infrastructure Target**: Tests target **existing deployed infrastructure**, not localhost
2. **Load Balancer Readiness**: Script waits up to 5 minutes for load balancers to be ready
3. **Backup Files**: Original configs are backed up with `.backup` extension
4. **Network Requirements**: Ensure kubectl can access your EKS cluster
5. **Rate Limits**: Be mindful of AWS API rate limits during intensive testing

## 🛠️ **Troubleshooting**

### **kubectl Not Configured**
```bash
# Update kubeconfig for EKS
aws eks update-kubeconfig --region us-east-2 --name dev-eks-us-east-2

# Verify connectivity
kubectl cluster-info
```

### **Load Balancer Not Ready**
```bash
# Check service status
kubectl get svc -A | grep LoadBalancer

# Check load balancer events
kubectl describe svc frontend-service -n frontend-dev
```

### **Artillery Installation**
```bash
# Install Artillery globally
npm install -g artillery

# Or use Makefile target
make install-artillery
```

### **Backup Recovery**
```bash
# Restore original configs if needed
cp Code/server/src/tests/stresstests/stress_server.yml.backup \
   Code/server/src/tests/stresstests/stress_server.yml
```

## 📋 **Makefile Targets**

| Target | Description |
|--------|-------------|
| `make update-load-test-urls` | Update Artillery configs with current URLs |
| `make run-load-tests` | Run comprehensive load tests |
| `make run-backend-load-test` | Run backend load tests only |
| `make run-frontend-load-test` | Run frontend load tests only |
| `make run-quick-load-test` | Run quick/basic load tests |
| `make install-artillery` | Install Artillery load testing tool |

## 🔗 **References**

- [Artillery.io Documentation](https://artillery.io/docs/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Multi-Cloud Load Testing Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/load-testing/) 