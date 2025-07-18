#!/bin/bash

# 수집할 정보를 저장할 디렉토리 생성
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="cluster_diagnosis_$TIMESTAMP"
mkdir -p "$LOG_DIR"

# 대상 파드들
PODS=("kube-apiserver-k1" "kube-apiserver-k2" "kube-apiserver-k3" 
      "kube-controller-manager-k1" "kube-controller-manager-k2" "kube-controller-manager-k3" 
      "kube-scheduler-k1" "kube-scheduler-k2" "kube-scheduler-k3")

# 노드 목록
NODES=("k1" "k2" "k3" "k4")

# 의존성 파드들
DEPENDENT_PODS=("etcd-k1" "etcd-k2" "etcd-k3" "coredns-847b7d995f-7fx64" "coredns-847b7d995f-kjbq5")

# 통합 파일 경로
POD_LOGS="$LOG_DIR/pod_logs.txt"
POD_DESCRIPTIONS="$LOG_DIR/pod_descriptions.txt"
NODE_DESCRIPTIONS="$LOG_DIR/node_descriptions.txt"
RESOURCE_USAGE="$LOG_DIR/resource_usage.txt"
SYSTEM_LOGS="$LOG_DIR/system_logs.txt"
NETWORK_TESTS="$LOG_DIR/network_tests.txt"
KUBERNETES_EVENTS="$LOG_DIR/kubernetes_events.txt"
POD_YAML="$LOG_DIR/pod_yaml.txt"
CONTAINER_IMAGES="$LOG_DIR/container_images.txt"
DEPENDENT_PODS_FILE="$LOG_DIR/dependent_pods.txt"

# 파일 초기화
> "$POD_LOGS"
> "$POD_DESCRIPTIONS"
> "$NODE_DESCRIPTIONS"
> "$RESOURCE_USAGE"
> "$SYSTEM_LOGS"
> "$NETWORK_TESTS"
> "$KUBERNETES_EVENTS"
> "$POD_YAML"
> "$CONTAINER_IMAGES"
> "$DEPENDENT_PODS_FILE"

# 1. 파드의 로그 수집
echo "Collecting pod logs..."
for POD in "${PODS[@]}"; do
  echo "=== Logs for $POD ===" >> "$POD_LOGS"
  kubectl logs -n kube-system $POD >> "$POD_LOGS" 2>&1
  echo -e "\n" >> "$POD_LOGS"
done

# 2. 파드의 상태 및 이벤트 확인
echo "Collecting pod descriptions..."
for POD in "${PODS[@]}"; do
  echo "=== Description for $POD ===" >> "$POD_DESCRIPTIONS"
  kubectl describe pod -n kube-system $POD >> "$POD_DESCRIPTIONS" 2>&1
  echo -e "\n" >> "$POD_DESCRIPTIONS"
done

# 3. 노드의 상태 확인
echo "Collecting node information..."
echo "=== Node List ===" >> "$NODE_DESCRIPTIONS"
kubectl get nodes >> "$NODE_DESCRIPTIONS" 2>&1
echo -e "\n" >> "$NODE_DESCRIPTIONS"
for NODE in "${NODES[@]}"; do
  echo "=== Description for node $NODE ===" >> "$NODE_DESCRIPTIONS"
  kubectl describe node $NODE >> "$NODE_DESCRIPTIONS" 2>&1
  echo -e "\n" >> "$NODE_DESCRIPTIONS"
done

# 4. 리소스 사용량 확인
echo "Collecting resource usage..."
echo "=== Node Resource Usage ===" >> "$RESOURCE_USAGE"
kubectl top node >> "$RESOURCE_USAGE" 2>&1
echo -e "\n" >> "$RESOURCE_USAGE"
echo "=== Pod Resource Usage in kube-system ===" >> "$RESOURCE_USAGE"
kubectl top pod -n kube-system >> "$RESOURCE_USAGE" 2>&1
echo -e "\n" >> "$RESOURCE_USAGE"

# 5. 시스템 로그 수집
echo "Collecting system logs from nodes..."
for NODE in "${NODES[@]}"; do
  echo "=== Syslog for $NODE ===" >> "$SYSTEM_LOGS"
  ssh $NODE "sudo tail -n 100 /var/log/syslog" >> "$SYSTEM_LOGS" 2>&1
  echo -e "\n" >> "$SYSTEM_LOGS"
  echo "=== Messages for $NODE ===" >> "$SYSTEM_LOGS"
  ssh $NODE "sudo tail -n 100 /var/log/messages" >> "$SYSTEM_LOGS" 2>&1
  echo -e "\n" >> "$SYSTEM_LOGS"
done

# 6. 네트워크 연결 확인 (노드 간 ping 테스트)
echo "Testing network connectivity between nodes..."
for NODE1 in "${NODES[@]}"; do
  for NODE2 in "${NODES[@]}"; do
    if [ "$NODE1" != "$NODE2" ]; then
      echo "=== Ping from $NODE1 to $NODE2 ===" >> "$NETWORK_TESTS"
      ssh $NODE1 "ping -c 3 $NODE2" >> "$NETWORK_TESTS" 2>&1
      echo -e "\n" >> "$NETWORK_TESTS"
    fi
  done
done

# 7. Kubernetes 이벤트 확인
echo "Collecting Kubernetes events..."
kubectl get events -n kube-system >> "$KUBERNETES_EVENTS" 2>&1

# 8. 파드의 YAML 파일 수집
echo "Collecting pod YAML files..."
for POD in "${PODS[@]}"; do
  echo "=== YAML for $POD ===" >> "$POD_YAML"
  kubectl get pod -n kube-system $POD -o yaml >> "$POD_YAML" 2>&1
  echo -e "\n" >> "$POD_YAML"
done

# 9. 컨테이너 이미지 확인
echo "Checking container images..."
for POD in "${PODS[@]}"; do
  echo "=== Images for $POD ===" >> "$CONTAINER_IMAGES"
  kubectl get pod -n kube-system $POD -o jsonpath='{.spec.containers[*].image}' >> "$CONTAINER_IMAGES" 2>&1
  echo -e "\n" >> "$CONTAINER_IMAGES"
done

# 10. 의존성 파드 확인
echo "Checking dependent pods..."
for POD in "${DEPENDENT_PODS[@]}"; do
  echo "=== Description for dependent pod $POD ===" >> "$DEPENDENT_PODS_FILE"
  kubectl describe pod -n kube-system $POD >> "$DEPENDENT_PODS_FILE" 2>&1
  echo -e "\n" >> "$DEPENDENT_PODS_FILE"
done

echo "Diagnosis information collected in $LOG_DIR"
