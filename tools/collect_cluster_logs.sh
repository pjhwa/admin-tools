#!/bin/bash

# 모든 결과물을 저장할 로그 파일 이름을 지정합니다.
LOG_FILE="cluster_diagnostics_$(date +%Y%m%d_%H%M%S).log"

# 모든 출력을 화면과 파일에 동시에 기록합니다.
exec &> >(tee -a "$LOG_FILE")

echo "========================================================================"
echo "=== 클러스터 진단 정보 수집 시작: $(date)"
echo "========================================================================"

# --- 1. kubectl을 통한 클러스터 전반 정보 수집 ---
echo -e "\n\n### 1.1. Kubernetes 노드 상태 ###"
kubectl get nodes -o wide

echo -e "\n\n### 1.2. 노드 별 리소스 사용량 (Top) ###"
kubectl top nodes

echo -e "\n\n### 1.3. 전체 Pod 리소스 사용량 (Top, 모든 네임스페이스) ###"
kubectl top pods -A --sort-by=cpu

# --- 2. 컨트롤 플레인 핵심 컴포넌트 로그 수집 ---
echo -e "\n\n### 2.1. Kube API 서버 로그 (최근 100줄) ###"
APISERVER_PODS=$(kubectl -n kube-system get pods -l component=kube-apiserver -o jsonpath='{.items[*].metadata.name}')
for pod in $APISERVER_PODS; do
  echo "--- $pod 로그 ---"
  kubectl -n kube-system logs --tail=100 "$pod"
  echo "------"
done

echo -e "\n\n### 2.2. Kube Controller Manager 로그 (최근 100줄) ###"
CONTROLLER_PODS=$(kubectl -n kube-system get pods -l component=kube-controller-manager -o jsonpath='{.items[*].metadata.name}')
for pod in $CONTROLLER_PODS; do
  echo "--- $pod 로그 ---"
  kubectl -n kube-system logs --tail=100 "$pod"
  echo "------"
done

# --- 3. SSH를 통한 개별 노드 상세 정보 수집 ---
# kubectl로 노드 목록을 가져옵니다.
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $NODES; do
  echo -e "\n\n========================================================================"
  echo "=== 노드 상세 정보 수집 중: $node"
  echo "========================================================================"

  echo -e "\n### 3.1. Kubelet 로그 (최근 15분) on $node ###"
  ssh "$node" 'journalctl -u kubelet --since "15 minutes ago" --no-pager'

  echo -e "\n### 3.2. 커널 메시지 (dmesg) on $node ###"
  ssh "$node" 'dmesg -T'

  echo -e "\n### 3.3. 시스템 프로세스 (top) on $node ###"
  ssh "$node" 'top -bn1'

  echo -e "\n### 3.4. 디스크 사용량 (df -h) on $node ###"
  ssh "$node" 'df -h'

  echo -e "\n### 3.5. 메모리 사용량 (free -h) on $node ###"
  ssh "$node" 'free -h'

  echo -e "\n### 3.6. I/O 상태 (iostat) on $node ###"
  ssh "$node" 'iostat -xz 1 5'
done

echo -e "\n\n========================================================================"
echo "=== 클러스터 진단 정보 수집 완료: $(date)"
echo "=== 모든 정보가 ${LOG_FILE} 파일에 저장되었습니다."
echo "========================================================================"
