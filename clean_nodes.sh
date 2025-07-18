#!/bin/bash

for node in k1 k2 k3 k4; do
	banner "$node reset"
	ssh citec@$node 'bash -s' < reset_script.sh
done
