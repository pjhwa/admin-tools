#!/bin/bash

# Set OpenStack authentication environment variables according to your environment
export OS_AUTH_URL=http://keystone.citec.com/v3
export OS_PROJECT_DOMAIN_NAME=default
export OS_USERNAME=admin
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

# Redirect output to both console and log file for reference
exec > >(tee -a getinfo.log) 2>&1

# Timestamp for when the information is gathered
echo "=== Timestamp ==="
date
echo ""

# Kubernetes Cluster Information
echo "=== Kubernetes Cluster Information ==="
echo ">>> Nodes with Labels"
kubectl get nodes --show-labels
echo ""
echo ">>> Persistent Volumes (All Namespaces)"
kubectl get pv -A
echo ""
echo ">>> Persistent Volume Claims (All Namespaces)"
kubectl get pvc -A
echo ""

# OpenStack Namespace Resources
echo "=== OpenStack Namespace Resources ==="
echo ">>> Pods with Extended Details"
kubectl -n openstack get pods -o wide
echo ""

# Identify and describe non-running pods
non_running_pods=$(kubectl -n openstack get pods --field-selector=status.phase!=Running -o name)
if [ -n "$non_running_pods" ]; then
    echo "=== Non-Running Pods ==="
    for pod in $non_running_pods; do
        echo ">>> Describing $pod"
        kubectl -n openstack describe $pod
        echo ""
    done
fi

echo ">>> Services with Extended Details"
kubectl -n openstack get services -o wide
echo ""
echo ">>> Endpoints"
kubectl -n openstack get endpoints
echo ""
echo ">>> Deployments"
kubectl -n openstack get deployments
echo ""
echo ">>> StatefulSets"
kubectl -n openstack get statefulsets
echo ""
echo ">>> Secrets"
kubectl -n openstack get secrets
echo ""
echo ">>> ConfigMaps"
kubectl -n openstack get configmaps
echo ""
echo ">>> Network Policies"
kubectl -n openstack get networkpolicy
echo ""
echo ">>> Ingresses"
kubectl get ingress -n openstack
echo ""

# Identify and describe unbound PVCs
unbound_pvcs=$(kubectl -n openstack get pvc --field-selector=status.phase!=Bound -o name)
if [ -n "$unbound_pvcs" ]; then
    echo "=== Unbound PVCs ==="
    for pvc in $unbound_pvcs; do
        echo ">>> Describing $pvc"
        kubectl -n openstack describe $pvc
        echo ""
    done
fi

echo ">>> Recent Events (Sorted by Timestamp)"
kubectl -n openstack get events --sort-by=.metadata.creationTimestamp
echo ""

# Helm Charts in OpenStack Namespace
echo "=== Helm Charts in OpenStack Namespace ==="
echo ">>> Helm Releases"
helm list -n openstack
echo ""

# OpenStack Service Information
echo "=== OpenStack Service Information ==="
echo ">>> Registered Services"
openstack service list
echo ""
echo ">>> Service Endpoints"
openstack endpoint list
echo ""
echo ">>> Networks"
openstack network list
echo ""
echo ">>> Network Agents"
openstack network agent list
echo ""

# Resource Usage Information
echo "=== Resource Usage ==="
echo ">>> Node Resource Usage"
kubectl top nodes
echo ""
echo ">>> Pod Resource Usage in OpenStack Namespace"
kubectl top pods -n openstack
echo ""
