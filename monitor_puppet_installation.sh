#!/bin/bash

# Puppet Enterprise Installation Monitor
PE_IP="3.145.180.244"
START_TIME=$(date +%s)

echo "🚀 Puppet Enterprise Installation Monitor"
echo "📍 Instance: $PE_IP"
echo "⏰ Started: $(date)"
echo "════════════════════════════════════════════════════════════════"

# Function to check if a port is open
check_port() {
    timeout 3 bash -c "</dev/tcp/$1/$2" >/dev/null 2>&1
    return $?
}

# Function to check HTTP service
check_http() {
    local url=$1
    local service_name=$2
    if curl -s -k --connect-timeout 3 --max-time 5 "$url" >/dev/null 2>&1; then
        echo "✅ $service_name is responding"
        return 0
    else
        echo "⏳ $service_name not ready yet"
        return 1
    fi
}

# Function to show elapsed time
show_elapsed() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    printf "⏱️  Elapsed: %02d:%02d\n" $minutes $seconds
}

# Service check function
check_services() {
    echo ""
    echo "📊 Service Status Check:"
    echo "----------------------------------------"
    
    # Check SSH (should be available quickly)
    if check_port $PE_IP 22; then
        echo "✅ SSH (22) - Instance is accessible"
    else
        echo "❌ SSH (22) - Instance not ready"
    fi
    
    # Check Puppet Enterprise Services
    local services_ready=0
    
    # PE Console (443)
    if check_port $PE_IP 443; then
        echo "✅ PE Console (443) - Service started"
        ((services_ready++))
        check_http "https://$PE_IP" "PE Console"
    else
        echo "⏳ PE Console (443) - Installing..."
    fi
    
    # Puppet Server (8140)
    if check_port $PE_IP 8140; then
        echo "✅ Puppet Server (8140) - Service started"
        ((services_ready++))
    else
        echo "⏳ Puppet Server (8140) - Installing..."
    fi
    
    # PuppetDB (8081)
    if check_port $PE_IP 8081; then
        echo "✅ PuppetDB (8081) - Service started"
        ((services_ready++))
    else
        echo "⏳ PuppetDB (8081) - Installing..."
    fi
    
    # Orchestrator (8142)
    if check_port $PE_IP 8142; then
        echo "✅ Orchestrator (8142) - Service started"
        ((services_ready++))
    else
        echo "⏳ Orchestrator (8142) - Installing..."
    fi
    
    # Code Manager (8170)
    if check_port $PE_IP 8170; then
        echo "✅ Code Manager (8170) - Service started"
        ((services_ready++))
    else
        echo "⏳ Code Manager (8170) - Installing..."
    fi
    
    echo "----------------------------------------"
    echo "📈 Progress: $services_ready/5 services ready"
    
    return $services_ready
}

# Main monitoring loop
echo ""
echo "Starting continuous monitoring (Ctrl+C to stop)..."
echo "Expected installation time: 15-20 minutes"
echo ""

iteration=0
while true; do
    ((iteration++))
    
    echo "📋 Check #$iteration - $(date '+%H:%M:%S')"
    show_elapsed
    
    check_services
    services_count=$?
    
    if [ $services_count -eq 5 ]; then
        echo ""
        echo "🎉 SUCCESS! All Puppet Enterprise services are ready!"
        echo "🌐 PE Console: https://$PE_IP"
        echo "🔑 Admin Username: admin"
        echo "💡 Get admin password: aws secretsmanager get-secret-value --secret-id dev-puppet-admin-password --query SecretString --output text"
        break
    fi
    
    echo "⏳ Installation in progress... checking again in 30 seconds"
    echo "════════════════════════════════════════════════════════════════"
    sleep 30
done

echo ""
echo "✅ Monitoring complete!" 