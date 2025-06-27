# Consul Multi-Cloud Service Discovery & Service Mesh

This module provides HashiCorp Consul deployment across your multi-cloud infrastructure.

## Architecture

- **Primary Datacenter**: AWS EC2-based Consul server cluster (3 nodes)
- **Secondary Datacenters**: Kubernetes-based Consul clients in EKS and GKE
- **WAN Federation**: Secure communication between datacenters
- **Service Mesh**: Consul Connect with automatic mTLS

## Features

- 🌐 Multi-cloud service discovery
- 🔒 Zero-trust service mesh with mTLS
- 📊 Prometheus metrics integration
- 🎯 Automatic sidecar injection in Kubernetes
- 🔄 Cross-cloud service catalog sync

## Deployment

Deployed automatically with:
```bash
make apply ENV=dev REGION=us-east-2
```

## Usage

Check status:
```bash
make consul-status ENV=dev REGION=us-east-2
```

Enable service mesh in Kubernetes:
```yaml
annotations:
  consul.hashicorp.com/connect-inject: "true"
```

## Components

- `ec2-cluster/`: Primary Consul server cluster on AWS EC2
- `k8s-client/`: Consul clients for Kubernetes clusters

See individual module READMEs for detailed configuration options. 