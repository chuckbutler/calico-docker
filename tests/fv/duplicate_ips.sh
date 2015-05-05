#!/bin/sh
set -e
set -x
show_commands() {
dist/calicoctl status
dist/calicoctl shownodes --detailed
dist/calicoctl ipv4 pool show
dist/calicoctl profile show --detailed
}

# Set it up
docker rm -f node1 node2 etcd || true
docker run -d --net=host --name etcd quay.io/coreos/etcd:v2.0.10
dist/calicoctl reset || true

show_commands
dist/calicoctl node --ip=127.0.0.1
dist/calicoctl profile add TEST_GROUP

# Add endpoints
export DOCKER_HOST=localhost:2377
while ! docker ps; do
echo "Waiting for powerstrip to come up"
  sleep 1
done

# Add two endpoints with the same IP address
docker run -e CALICO_IP=192.168.1.1 -tid --name=node1 busybox
docker run -e CALICO_IP=192.168.1.1 -tid --name=node2 busybox 

dist/calicoctl profile TEST_GROUP member add node1
dist/calicoctl profile TEST_GROUP member add node2

# Check the config looks good
show_commands

# Check it works
while ! docker exec node1 ping 192.168.1.1 -c 1 -W 1; do
echo "Waiting for network to come up"
  sleep 1
done

docker exec node1 ping 192.168.1.1 -c 1
docker exec node2 ping 192.168.1.1 -c 1

# Remove the ip from one of the containers & make sure it still works
dist/calicoctl ipv4 container node2 remove 192.168.1.1
docker exec node1 ping 192.168.1.1 -c 1
docker exec node2 ping 192.168.1.1 -c 1

# Then remove the whole container & make sure it still works
dist/calicoctl container remove node2
docker exec node1 ping 192.168.1.1 -c 1

# Tear it down
dist/calicoctl profile remove TEST_GROUP
show_commands

dist/calicoctl container remove node1
show_commands

dist/calicoctl ipv4 pool remove 192.168.0.0/16
show_commands

export DOCKER_HOST=
dist/calicoctl node stop
show_commands
