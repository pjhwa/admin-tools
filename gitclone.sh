#!/bin/bash

for node in k2 k3 k4; do
	ssh citec@$node 'sudo rm -rf admin-tools'
	banner "$node Git Cloning"
	ssh citec@$node 'git clone https://github.com/pjhwa/admin-tools.git'
done
