# admin-tools

gitclone.sh : 각 노드에 admin-tools 리포지토리 클론
clean_containers.sh : k8s 운영 중 불필요한 컨테이너들 정리
clean_nodes.sh : reset_script.sh 호출하여 전체 노드에 k8s 초기화(삭제)
reset_script.sh : k8s 초기화

./tmp:
hosts.tmp
resolv.conf.tmp

./tools:
collect_cluster_logs.sh : k8s 클러스터 로그 수집
kubecluster_diag.sh : k8s 클러스터 진단 정보 수집
os-getinfo.sh : openstack 파드 정보 수집
