#!/bin/bash

for node in k1 k2 k3 k4
do
	banner ${node}
	echo "Cleaning containerd..."
	ssh citec@${node} "sudo ctr -n k8s.io images ls -q | xargs sudo ctr -n k8s.io images rm"
	echo "Cleaning docker..."
	ssh citec@${node} "sudo docker system prune -a --volumes"
	echo "Cleaning snapd..."
	ssh citec@${node} "sudo snap list --all | awk '/disabled/ {print \$1 \" \" \$3}' | while read snapname revision; do sudo snap remove \"\$snapname\" --revision=\"\$revision\"; done"
	echo "Cleaning journal logs..."
	ssh citec@${node} "sudo journalctl --vacuum-time=7d"
	echo "Cleaning /var/log/ logs..."
	ssh citec@${node} "sudo find /var/log -type f -name '*.gz' -delete"
        #ssh citec@${node } "sudo find /var/log -type f -name '*.log.'" -delete
	GB=$(ssh citec@${node} df -h / | grep -v Filesystem | awk '{print $5}'); banner "USE: $GB"
done
