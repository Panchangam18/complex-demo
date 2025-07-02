#!/usr/bin/env python3
"""
Dynamic Ansible inventory script that sources from Terraform state
This implements the architecture plan requirement: "Inventory sourced from Terraform state via terraform-inv"
"""

import json
import subprocess
import sys
import os
from collections import defaultdict

def get_terraform_output():
    """Get Terraform outputs from the current state"""
    try:
        # Change to the terraform directory
        terraform_dir = os.path.join(os.path.dirname(__file__), '../../terraform/envs/dev/us-east-2')
        
        # Get Terraform output
        result = subprocess.run(
            ['terragrunt', 'output', '-json'],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            check=True
        )
        
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error getting Terraform output: {e}", file=sys.stderr)
        return {}
    except json.JSONDecodeError as e:
        print(f"Error parsing Terraform JSON: {e}", file=sys.stderr)
        return {}

def build_inventory():
    """Build Ansible inventory from Terraform state"""
    
    terraform_outputs = get_terraform_output()
    
    inventory = {
        '_meta': {
            'hostvars': {}
        }
    }
    
    # Initialize groups
    groups = defaultdict(lambda: {'hosts': [], 'vars': {}})
    
    # Process Consul servers (AWS EC2)
    if 'consul_primary_datacenter' in terraform_outputs:
        consul_info = terraform_outputs['consul_primary_datacenter']['value']
        
        for i, server_ip in enumerate(consul_info.get('server_private_ips', [])):
            hostname = f"consul-server-{i+1}"
            groups['consul_servers']['hosts'].append(hostname)
            groups['aws_instances']['hosts'].append(hostname)
            groups['day0_provisioning']['hosts'].append(hostname)
            
            inventory['_meta']['hostvars'][hostname] = {
                'ansible_host': server_ip,
                'ansible_user': 'ec2-user',
                'ansible_ssh_private_key_file': '~/.ssh/aws-consul-key.pem',
                'consul_role': 'server',
                'consul_datacenter': consul_info.get('datacenter_name', 'aws-dev-us-east-2'),
                'cloud_provider': 'aws',
                'environment': 'dev',
                'puppet_environment': 'production',
                'puppet_server': terraform_outputs.get('puppet_server_url', {}).get('value', ''),
                'config_management': 'puppet',
                'day_2_ops': True
            }
    
    # Process Jenkins server
    if 'jenkins_public_ip' in terraform_outputs:
        jenkins_ip = terraform_outputs['jenkins_public_ip']['value']
        hostname = 'jenkins-server'
        
        groups['jenkins_servers']['hosts'].append(hostname)
        groups['aws_instances']['hosts'].append(hostname)
        groups['day0_provisioning']['hosts'].append(hostname)
        groups['ci_cd_servers']['hosts'].append(hostname)
        
        inventory['_meta']['hostvars'][hostname] = {
            'ansible_host': jenkins_ip,
            'ansible_user': 'ec2-user',
            'ansible_ssh_private_key_file': '~/.ssh/aws-jenkins-key.pem',
            'service_type': 'jenkins',
            'cloud_provider': 'aws',
            'environment': 'dev',
            'puppet_environment': 'production',
            'puppet_server': terraform_outputs.get('puppet_server_url', {}).get('value', ''),
            'config_management': 'puppet',
            'day_2_ops': True,
            'consul_service_name': 'jenkins-ci',
            'consul_service_port': 8080
        }
    
    # Process Puppet Enterprise server
    if 'puppet_enterprise_public_ip' in terraform_outputs:
        puppet_ip = terraform_outputs['puppet_enterprise_public_ip']['value']
        hostname = 'puppet-enterprise-server'
        
        groups['puppet_servers']['hosts'].append(hostname)
        groups['aws_instances']['hosts'].append(hostname)
        groups['day0_provisioning']['hosts'].append(hostname)
        groups['config_management_servers']['hosts'].append(hostname)
        
        inventory['_meta']['hostvars'][hostname] = {
            'ansible_host': puppet_ip,
            'ansible_user': 'ec2-user',
            'ansible_ssh_private_key_file': '~/.ssh/aws-puppet-key.pem',
            'service_type': 'puppet-enterprise',
            'cloud_provider': 'aws',
            'environment': 'dev',
            'puppet_role': 'master',
            'config_management': 'self-managed',
            'day_2_ops': False,  # Puppet master doesn't manage itself
            'consul_service_name': 'puppet-enterprise',
            'consul_service_port': 443
        }
    
    # Process EKS nodes (dynamically discovered)
    # Note: EKS nodes are managed by AWS via daemonsets, not SSH
    if 'eks_cluster_id' in terraform_outputs:
        eks_cluster = terraform_outputs['eks_cluster_id']['value']
        
        groups['kubernetes_nodes']['vars'] = {
            'cluster_type': 'eks',
            'cloud_provider': 'aws',
            'consul_service_mesh': True,
            'puppet_sidecar': True
        }
        
        # Kubernetes clusters managed via kubectl/daemonsets, not SSH
        groups['kubernetes_clusters']['hosts'].append('eks-dev-us-east-2')
        inventory['_meta']['hostvars']['eks-dev-us-east-2'] = {
            'cluster_name': eks_cluster,
            'cluster_type': 'eks',
            'cloud_provider': 'aws',
            'environment': 'dev',
            'consul_datacenter': 'eks-dev-us-east-2',
            'puppet_environment': 'production',
            'config_management': 'kubernetes-daemonset',
            'skip_ssh': True  # Flag to exclude from SSH-based provisioning
        }
    
    # Process GKE nodes (dynamically discovered)
    # Note: GKE nodes are managed by GCP via daemonsets, not SSH
    if 'gke_cluster_name' in terraform_outputs:
        gke_cluster = terraform_outputs['gke_cluster_name']['value']
        
        groups['kubernetes_clusters']['hosts'].append('gke-dev-us-east1')
        inventory['_meta']['hostvars']['gke-dev-us-east1'] = {
            'cluster_name': gke_cluster,
            'cluster_type': 'gke',
            'cloud_provider': 'gcp',
            'environment': 'dev',
            'consul_datacenter': 'gke-dev-us-east1',
            'puppet_environment': 'production',
            'config_management': 'kubernetes-daemonset',
            'skip_ssh': True  # Flag to exclude from SSH-based provisioning
        }
    
    # Process AKS nodes (dynamically discovered)  
    # Note: AKS nodes are managed by Azure via daemonsets, not SSH
    if 'aks_cluster_name' in terraform_outputs:
        aks_cluster = terraform_outputs['aks_cluster_name']['value']
        
        groups['kubernetes_clusters']['hosts'].append('aks-dev-eastus')
        inventory['_meta']['hostvars']['aks-dev-eastus'] = {
            'cluster_name': aks_cluster,
            'cluster_type': 'aks',
            'cloud_provider': 'azure',
            'environment': 'dev',
            'consul_datacenter': 'aks-dev-eastus',
            'puppet_environment': 'production',
            'config_management': 'kubernetes-daemonset',
            'skip_ssh': True  # Flag to exclude from SSH-based provisioning
        }
    
    # Add group variables
    groups['all']['vars'] = {
        'environment': 'dev',
        'puppet_server': terraform_outputs.get('puppet_server_url', {}).get('value', ''),
        'consul_ui_url': terraform_outputs.get('consul_ui_url', {}).get('value', ''),
        'ansible_python_interpreter': '/usr/bin/python3'
    }
    
    groups['aws_instances']['vars'] = {
        'cloud_provider': 'aws',
        'ansible_ssh_common_args': '-o StrictHostKeyChecking=no'
    }
    
    groups['day0_provisioning']['vars'] = {
        'provisioning_phase': 'day0',
        'install_consul_agent': True,
        'configure_puppet_agent': True,
        'enable_monitoring': True
    }
    
    groups['config_management_servers']['vars'] = {
        'puppet_role': 'master',
        'consul_service_registration': True
    }
    
    # Convert defaultdict to regular dict for JSON serialization
    for group_name, group_data in groups.items():
        inventory[group_name] = dict(group_data)
    
    return inventory

def main():
    """Main entry point"""
    if len(sys.argv) == 2 and sys.argv[1] == '--list':
        inventory = build_inventory()
        print(json.dumps(inventory, indent=2))
    elif len(sys.argv) == 3 and sys.argv[1] == '--host':
        # Return empty dict for host-specific vars (we use group vars)
        print(json.dumps({}))
    else:
        print("Usage: terraform-inventory.py --list | --host <hostname>", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main() 