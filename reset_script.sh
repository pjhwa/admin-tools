#!/bin/bash

# 스크립트 실행 전 확인 메시지
echo "이 스크립트는 Kubernetes, Docker, Calico 등 모든 구성을 제거하고 OS를 초기화합니다."
#echo "계속하려면 'yes'를 입력하세요."
#read -r confirm
#if [ "$confirm" != "yes" ]; then
#    echo "초기화가 취소되었습니다."
#    exit 1
#fi

# 1. 패키지 제거
echo "Kubernetes, Docker, Containerd 패키지를 제거합니다..."
sudo kubeadm reset -f --cri-socket unix:///var/run/containerd/containerd.sock 2> /dev/null
sudo apt-get remove -y kubelet kubeadm kubectl 2> /dev/null
sudo apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2> /dev/null
sudo apt-get remove -y calicoctl 2> /dev/null
sudo apt-get remove -y haproxy keepalived 2> /dev/null
sudo helm plugin uninstall openstack 2> /dev/null
export KUBECONFIG=""

# 2. 설정 파일 및 디렉터리 제거
echo "설정 파일 및 디렉터리를 제거합니다..."
sudo rm -rf /etc/apt/sources.list.d/docker.list
sudo rm -rf /etc/apt/sources.list.d/kubernetes.list
sudo rm -rf /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo rm -rf ~/.kube/*
sudo rm -rf /etc/kubernetes/*
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/kubelet/*
sudo rm -rf /var/lib/cni/*
sudo rm -rf /var/lib/etcd/*
sudo rm -rf /etc/cni/net.d/*
sudo rm -rf /etc/ceph/*
sudo rm -rf /var/lib/ceph/*
sudo rm -rf /var/lib/rook/*
sudo rm -rf /var/log/ceph/*
sudo rm -rf /etc/haproxy/*
sudo rm -rf /etc/keepalived/*
sudo rm -rf /usr/local/bin/helm
sudo find /tmp -type f -exec rm {} \;

# 3. 네트워크 및 서비스 초기화
echo "네트워크 및 서비스를 초기화합니다..."
sudo iptables -F 2> /dev/null
sudo netstat -tulpn | grep -E '6443|10259|10257|10250|2379|2380' | awk '{print $7}' | awk -F'/' '{print "kill -9 "$1}' | sh   2> /dev/null # 수정: $7 -> $6 (로그 확인)
sudo systemctl stop kubelet docker containerd || true 2> /dev/null
sudo ip link delete kube-ipvs0 || true 2> /dev/null
sudo ip link delete docker0 || true 2> /dev/null
sudo ip addr del 172.16.2.148/24 dev ens160 || true 2> /dev/null
# 추가: Calico 인터페이스 삭제
sudo ip link delete cali* || true 2> /dev/null  # Calico 인터페이스 삭제
sudo ip link delete tunl0 || true 2> /dev/null  # IPIP 터널 삭제 (Calico 사용 시)
sudo rm -rf /etc/calico /var/lib/calico  # Calico 구성 삭제

# 4. 컨테이너 및 이미지 정리 (필요 시)
echo "컨테이너 및 이미지를 정리합니다..."
sudo crictl --runtime-endpoint=unix:///run/containerd/containerd.sock stop $(sudo crictl --runtime-endpoint=unix:///run/containerd/containerd.sock ps -q) 2>/dev/null || true > /dev/null 2>&1
sudo crictl --runtime-endpoint=unix:///run/containerd/containerd.sock rm $(sudo crictl --runtime-endpoint=unix:///run/containerd/containerd.sock ps -a -q) 2>/dev/null || true > /dev/null 2>&1
#sudo docker stop $(sudo docker ps -aq) 2>/dev/null || true
#sudo docker rm $(sudo docker ps -aq) 2>/dev/null || true
#sudo docker rmi $(sudo docker images -q) 2>/dev/null || true

# 5. 시스템 파일 복원 (백업 파일이 있는 경우)
echo "시스템 파일을 복원합니다..."
if [ -f "/home/citec/admin-tools/tmp/resolv.conf.tmp" ]; then
    sudo cp /home/citec/admin-tools/tmp/resolv.conf.tmp /etc/resolv.conf
else
    echo "resolv.conf 백업 파일이 없습니다. 수동 복원이 필요할 수 있습니다."
fi
if [ -f "/home/citec/admin-tools/tmp/hosts.tmp" ]; then
    sudo cp /home/citec/admin-tools/tmp/hosts.tmp /etc/hosts
else
    echo "hosts 백업 파일이 없습니다. 수동 복원이 필요할 수 있습니다."
fi

# 6. 패키지 캐시 및 의존성 정리
echo "패키지 캐시를 정리합니다..."
sudo apt-get autoremove -y 2> /dev/null
sudo apt-get clean 2> /dev/null

# 7. 완료 메시지
echo "초기화가 완료되었습니다. 필요 시 시스템을 재부팅하세요."
# sudo reboot  # 재부팅이 필요하면 주석을 해제하세요
