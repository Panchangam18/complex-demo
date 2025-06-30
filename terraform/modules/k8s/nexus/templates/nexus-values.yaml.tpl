# Nexus 3 Helm Chart Values - Secure Version (stevehipwell/nexus3)
# Environment: ${environment}
# App Version: 3.81.1 (Secure - addresses CVE vulnerabilities)

# Image configuration (secure version)
image:
  repository: sonatype/nexus3
  tag: 3.81.1-java17-ubi
  pullPolicy: IfNotPresent

# Service configuration - LoadBalancer for external access
service:
  type: ${service_type}
  port: 8081
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"

# Ingress configuration (disabled since we use LoadBalancer)
ingress:
  enabled: ${ingress_enabled}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  hosts:
    - host: ${ingress_host}
      paths:
        - path: /

# Persistence configuration (disabled for demo)
persistence:
  enabled: false

# Resource limits
resources:
  requests:
    cpu: ${cpu_request}
    memory: ${memory_request}
  limits:
    cpu: ${cpu_limit}
    memory: ${memory_limit}

# Security context
securityContext:
  runAsUser: 200
  runAsGroup: 200
  fsGroup: 200

# Nexus configuration
nexus:
  properties:
    data: |-
      nexus.scripts.allowCreation=true
      nexus.cleanup.retainDays=30

# Environment variables for JVM tuning
env:
  - name: INSTALL4J_ADD_VM_PARAMS
    value: "-Xms512m -Xmx1g -XX:MaxDirectMemorySize=256m"
  - name: NEXUS_SECURITY_RANDOMPASSWORD
    value: "true" 