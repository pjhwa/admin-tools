### Kubernetes HA 마스터 클러스터 자동화 구성 가이드 (Kubespray 활용)

이 가이드에서는 사용자가 제공한 4개의 Ubuntu 22.04 VM을 기반으로 HA(High Availability) 마스터 Kubernetes 클러스터를 구성하는 방법을 설명합니다. 구성 목표는 다음과 같습니다:
- **마스터 노드**: 3개 (k1, k2, k3) – 이 노드들은 컨트롤 플레인 역할을 하면서 동시에 워커 노드 역할도 수행 (pods 스케줄링 허용).
- **워커 노드**: 4개 (k1, k2, k3, k4) – 모든 노드가 워커 역할을 함.
- **CNI**: Calico.
- **VIP (Virtual IP)**: 172.16.2.110 – API 서버의 HA를 위한 로드 밸런서 IP.
- **kubectl 사용자**: citec – 클러스터 접근을 위한 전용 사용자.
- **자동화 도구**: Ansible-playbook을 기반으로 Kubespray 프로젝트를 활용. Kubespray는 Ansible 스크립트를 사용해 Kubernetes 클러스터를 빠르고 반복적으로 배포할 수 있는 오픈소스 도구로, HA 구성, 다양한 CNI 지원, 커스터마이징이 용이합니다. OpenStack-Helm은 OpenStack 환경에 특화된 Helm 차트 기반 도구이지만, 여기서는 순수 Kubernetes 클러스터이므로 Kubespray를 선택했습니다. 이는 사실 기반으로 검증된 선택으로, Kubespray의 GitHub 리포지토리와 여러 튜토리얼에서 HA 클러스터 배포 사례가 풍부합니다.

**주의 사항 및 비판적 검증**:
- 이 구성은 Kubespray의 최신 버전 (현재 기준으로 v2.25.0 이상)을 기반으로 하며, Ubuntu 22.04와 호환됩니다. 그러나 Kubernetes 버전 (예: 1.29.x 또는 1.30.x)은 Kubespray의 기본 설정에 따라 달라질 수 있으므로, 배포 후 `kubectl version`으로 확인하세요. 만약 버전 호환성 문제가 발생하면 Kubespray 문서를 참조해 업그레이드하세요.
- HA 구성에서 VIP는 kube-vip (또는 HAProxy + Keepalived)을 사용해 구현되며, 이는 네트워크 안정성을 보장하지만, 실제 프로덕션 환경에서는 외부 LB (예: AWS ELB)를 고려하세요. Calico CNI는 BGP 기반 네트워킹으로 성능이 좋지만, 복잡한 네트워크에서 IP 충돌을 유발할 수 있으니 사전 테스트 필수.
- VM 스펙 (4 CPU, 32GB RAM, 3 HDD)은 Kubernetes HA에 충분하지만, 50GB HDD를 루트(/)로, 20GB를 /var/lib/kubelet으로, 16GB를 etcd 데이터로 할당하는 것을 추천. 이는 과부하 시 안정성을 높입니다.
- 보안 관점: 모든 단계에서 root 대신 sudo를 사용하고, SSH 키 기반 인증을 적용하세요. 방화벽은 ufw로 관리하며, 배포 후 CIS 벤치마크를 적용해 취약점 검증.
- 시간 소요: 초기 설정 30분, 배포 1-2시간 (네트워크 속도에 따라 다름). 실패 시 로그 (/var/log/ansible.log)를 분석하세요.
- 대안 검토: Kubeadm 직접 사용도 가능하지만, Ansible 자동화가 아니므로 Kubespray가 더 적합. OpenStack-Helm은 Helm에 의존해 복잡도가 높아 배제.

아래는 단계별 상세 설명입니다. 모든 명령어는 영어로 유지하며, 이해를 돕기 위해 각 단계의 이유와 잠재적 오류를 설명합니다.

#### 1. 전제 조건 설정 (모든 VM에서 수행)
클러스터 배포 전에 모든 VM을 준비합니다. 이는 Kubespray가 요구하는 기본 환경으로, swap off, hostname 설정, 패키지 업데이트 등입니다. citec 사용자를 생성하고 sudo 권한을 부여합니다.

- **각 VM에 로그인 (예: citec 사용자 생성)**:
  - 기본 사용자 (ubuntu)가 있다면 citec 생성:
    ```
    sudo adduser citec
    sudo usermod -aG sudo citec
    sudo passwd citec  # 비밀번호 설정
    ```
  - citec으로 전환: `su - citec`
  - 이유: kubectl 접근을 citec으로 제한해 보안 강화.

- **Hostname 및 IP 설정**:
  - 각 VM에서 hostname 설정 (이미 주어짐):
    ```
    sudo hostnamectl set-hostname k1  # k2, k3, k4에 맞게 변경
    ```
  - /etc/hosts에 모든 노드 추가 (DNS 대체):
    ```
    sudo tee -a /etc/hosts <<EOF
    172.16.2.111 k1
    172.16.2.112 k2
    172.16.2.113 k3
    172.16.2.114 k4
    172.16.2.110 kubernetes-vip  # VIP 추가
    EOF
    ```
  - 이유: 노드 간 통신을 위해 hostname resolution 필수. 오류 시 "unknown host" 발생.

- **시스템 업데이트 및 기본 설정**:
  ```
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y python3-pip net-tools curl
  sudo swapoff -a
  sudo sed -i '/swap/d' /etc/fstab  # 영구적으로 swap off
  sudo modprobe br_netfilter
  sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
  sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
  sudo sysctl -w net.ipv4.ip_forward=1
  sudo sysctl -p
  ```
  - 이유: Kubernetes는 swap을 허용하지 않으며, 브릿지 필터링이 네트워킹에 필요. 이 설정 없으면 pod 네트워크 실패.

- **방화벽 비활성화 (또는 포트 열기)**:
  ```
  sudo ufw disable
  ```
  - 이유: Calico CNI가 BGP 포트(179)를 사용하므로 방화벽 간섭 피함. 프로덕션에서는 ufw allow로 특정 포트(6443, 2379-2380 etcd 등)만 열기.

- **SSH 키 기반 인증 설정 (passwordless SSH)**:
  - citec 사용자에서 키 생성: `ssh-keygen -t rsa -b 4096`
  - 모든 노드에 공개키 복사: `ssh-copy-id citec@k1` (각 IP에 대해 반복, 비밀번호 입력).
  - 이유: Ansible이 SSH로 노드 접근하므로 필수. 오류 시 "permission denied" 발생.

- **HDD 마운트 (선택적, 하지만 추천)**:
  - 3개 HDD 확인: `lsblk`
  - 예: 50GB (/), 20GB (/var/lib/docker), 16GB (/var/lib/etcd)
    ```
    sudo mkfs.ext4 /dev/sdb  # 20GB
    sudo mkfs.ext4 /dev/sdc  # 16GB
    sudo mkdir -p /var/lib/docker /var/lib/etcd
    sudo mount /dev/sdb /var/lib/docker
    sudo mount /dev/sdc /var/lib/etcd
    sudo tee -a /etc/fstab <<EOF
    /dev/sdb /var/lib/docker ext4 defaults 0 0
    /dev/sdc /var/lib/etcd ext4 defaults 0 0
    EOF
    ```
  - 이유: Kubernetes 컴포넌트 (docker, etcd)가 대용량 저장소를 필요로 함. 기본 /로 하면 디스크 부족 위험.

이 단계는 모든 VM에서 반복. 완료 후 재부팅: `sudo reboot`.

#### 2. Ansible 컨트롤 노드 설정 (k1에서 수행)
Kubespray는 Ansible을 사용하므로, 하나의 노드 (여기서는 k1)를 컨트롤 노드로 사용합니다. k1은 마스터 노드이지만, Kubespray 배포 시 자체 포함 가능합니다.

- **Ansible 설치**:
  ```
  sudo apt install -y ansible git
  pip3 install -r https://raw.githubusercontent.com/kubernetes-sigs/kubespray/master/requirements.txt  # Jinja2 등 의존성
  ```
  - 이유: Kubespray가 Ansible 2.11+을 요구. 오류 시 "module not found" 발생.

- **Kubespray 클론**:
  ```
  git clone https://github.com/kubernetes-sigs/kubespray.git
  cd kubespray
  git checkout release-2.25  # 최신 stable 버전, 필요 시 업데이트
  ```
  - 이유: Kubespray는 GitHub에서 최신 코드를 가져옴. HA와 Calico 지원 확인.<grok:render card_id="f1f4e2" card_type="citation_card" type="render_inline_citation"><argument name="citation_id">0</argument></grok:render>

#### 3. 인벤토리 및 구성 파일 편집
Kubespray의 인벤토리를 사용자 환경에 맞게 커스터마이징합니다.

- **인벤토리 생성**:
  ```
  cp -rfp inventory/sample inventory/mycluster
  ```
  - hosts.yaml 편집 (vi inventory/mycluster/hosts.yaml):
    ```
    all:
      hosts:
        k1:
          ansible_host: 172.16.2.111
          ip: 172.16.2.111
          access_ip: 172.16.2.111
        k2:
          ansible_host: 172.16.2.112
          ip: 172.16.2.112
          access_ip: 172.16.2.112
        k3:
          ansible_host: 172.16.2.113
          ip: 172.16.2.113
          access_ip: 172.16.2.113
        k4:
          ansible_host: 172.16.2.114
          ip: 172.16.2.114
          access_ip: 172.16.2.114
      children:
        kube_control_plane:
          hosts:
            k1:
            k2:
            k3:
        etcd:
          hosts:
            k1:
            k2:
            k3:
        kube_node:
          hosts:
            k1:
            k2:
            k3:
            k4:
        k8s_cluster:
          children:
            kube_control_plane:
            kube_node:
        calico_rr:
          hosts: {}
    ```
  - 이유: kube_control_plane과 etcd를 3개 노드로 HA 구성. calico_rr은 BGP 라우터, 여기서는 비움 (Calico 기본 모드 사용).

- **클러스터 변수 편집 (group_vars/k8s_cluster/k8s-cluster.yml)**:
  - 주요 설정 추가/변경:
    ```
    kube_version: v1.29.0  # 원하는 Kubernetes 버전, 호환 확인
    kube_network_plugin: calico  # CNI: Calico 설정
    kube_proxy_mode: ipvs  # 성능 향상
    podsecuritypolicy_enabled: false  # 보안 정책 비활성 (테스트용)
    kubelet_deployment_type: host  # 호스트 기반
    kube_vip_enabled: true  # VIP를 위한 kube-vip 활성
    kube_vip_address: 172.16.2.110
    loadbalancer_apiserver:
      address: 172.16.2.110
      port: 6443
    apiserver_loadbalancer_domain_name: "kubernetes-vip"
    ```
  - 이유: HA를 위해 kube-vip 사용 (VIP 할당, 간단함). Calico는 network_plugin으로 지정. kube-vip은 마스터 노드에 daemonset으로 배포되어 VIP 관리.<grok:render card_id="5388af" card_type="citation_card" type="render_inline_citation"><argument name="citation_id">22</argument></grok:render> <grok:render card_id="305794" card_type="citation_card" type="render_inline_citation"><argument name="citation_id">20</argument></grok:render>
  - Calico 전용 파일 (group_vars/k8s_cluster/k8s-net-calico.yml) 확인: 기본값 유지, 필요 시 calico_backend: bird (BGP).

- **마스터 노드에서 pods 실행 허용**:
  - 배포 후 별도 단계지만, 미리 준비: Kubespray는 기본 taint 적용. playbook 실행 후 제거.

#### 4. 클러스터 배포 (Ansible-playbook 실행)
- 명령어:
  ```
  ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root -u citec cluster.yml
  ```
  - 옵션 설명: -i (인벤토리), --become (sudo), -u (사용자 citec).
  - 이유: 이 playbook이 모든 노드에 Kubernetes 컴포넌트 (kubeadm, kubelet, kubectl 등) 설치 및 초기화. HA는 자동으로 etcd 클러스터와 마스터 복제 처리. 시간: 30-60분.
  - 오류 대처: "failed to connect" 시 SSH 확인. 로그: ansible-playbook ... -vvv (verbose 모드).

#### 5. 배포 후 검증 및 마무리
- **클러스터 상태 확인 (k1에서)**:
  ```
  mkdir -p ~/.kube
  sudo cp /etc/kubernetes/admin.conf ~/.kube/config
  sudo chown citec:citec ~/.kube/config
  kubectl get nodes
  kubectl get pods --all-namespaces
  ```
  - 이유: admin.conf를 citec으로 복사해 kubectl 접근. 노드 4개 Ready 확인.

- **마스터 taint 제거 (pods 실행 허용)**:
  ```
  kubectl taint nodes k1 node-role.kubernetes.io/control-plane:NoSchedule-
  kubectl taint nodes k2 node-role.kubernetes.io/control-plane:NoSchedule-
  kubectl taint nodes k3 node-role.kubernetes.io/control-plane:NoSchedule-
  ```
  - 이유: 기본 taint로 마스터에 workload 금지. 제거 시 마스터도 워커 역할. Kubespray에서 이 옵션이 없으므로 수동.<grok:render card_id="f087fd" card_type="citation_card" type="render_inline_citation"><argument name="citation_id">28</argument></grok:render>

- **Calico 검증**:
  ```
  kubectl get pods -n calico-system
  ```
  - 모든 pods Running 확인. 이유: Calico가 CNI로 동작 중인지 확인.

- **HA 테스트**:
  - 하나의 마스터 다운: `sudo shutdown -h now` (k1), VIP로 `kubectl --server=https://172.16.2.110:6443 get nodes` 접근 확인.
  - 이유: kube-vip이 VIP failover 처리.

- **kubectl citec 사용자 설정**:
  - 다른 노드에도 ~/.kube/config 복사: `scp ~/.kube/config citec@k2:~/.kube/config` 등.
  - 이유: citec이 모든 노드에서 kubectl 사용 가능.

#### 잠재적 문제 및 비판적 검증
- **실패 원인**: 네트워크 지연 (VIP 할당 실패) – kube-vip 로그 확인 (`kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip`).
- **성능 검증**: 32GB RAM으로 충분하지만, 워크로드 증가 시 모니터링 (Prometheus 설치 추천).
- **보안**: 배포 후 RBAC 설정으로 citec 권한 제한. Kubespray는 기본 secure이지만, etcd 암호화 활성 확인.
- **대안**: 만약 Kubespray 실패 시 kubeadm 직접 HA (stacked etcd) 사용, 하지만 자동화 부족.<grok:render card_id="a623dc" card_type="citation_card" type="render_inline_citation"><argument name="citation_id">5</argument></grok:render>
- **업데이트**: Kubernetes 1.30+으로 업그레이드 시 `ansible-playbook upgrade-cluster.yml` 사용.

이 방법으로 1시간 이내 자동화 배포 가능. 추가 질문 시 로그 공유 부탁합니다.
