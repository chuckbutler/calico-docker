# Getting started with Calico on Docker

Calico provides IP connectivity between Docker containers on different hosts (as well as on the same host). These instructions use Vagrant and VirtualBox to set up a pair of Docker hosts, but any 64 bit Linux servers with a recent version of Docker and etcd (available on localhost:4001) should work. If you want to get started quickly and easily then we recommend just using Vagrant.

## Setting up a cluster of Docker hosts

If you don't already have Docker hosts available, you can set some up by running the following instructions on a Windows, Mac or Linux computer. If you've never used Vagrant, CoreOS or Etcd before then we recommend skimming their docs before running through these instructions.

### Initial environment setup

So, to get started, install Vagrant, Virtualbox and Git for your OS.
* https://www.virtualbox.org/wiki/Downloads (no need for the extensions, just the core package)
* https://www.vagrantup.com/downloads.html
* http://git-scm.com/downloads

Use the customized CoreOS-based Vagrant file from https://github.com/Metaswitch/calico-coreos-vagrant-example for streamlined setup. Follow the instructions there (and see the [CoreOS documentation](https://coreos.com/docs/running-coreos/platforms/vagrant/)).

You should now have two CoreOS servers, each running etcd in a cluster. The servers are named core-01 and core-02.  By default these have IP addresses 172.17.8.101 and 172.17.8.102. If you want to start again at any point, you can run

* `vagrant destroy`
* If you manually set the discovery URL in `user-data`, replace it with a fresh one.
* `vagrant up`

To connect to your servers
* Linux/MacOSX
   * `vagrant ssh <hostname>`
* Windows
   * Follow instructions from https://github.com/nickryand/vagrant-multi-putty
   * `vagrant putty <hostname>`

At this point, it's worth checking that your servers can ping each other.
* From core-01:
```
ping 172.17.8.102
```
* From core-02:
```
ping 172.17.8.101
```
If you see ping failures, the likely culprit is a problem with then Virtualbox network between the VMs.  Rebooting the host may help. Remember to shut down the VMs first with `vagrant halt` before you reboot.

## Starting Calico services

If you didn't use the calico-coreos-vagrant-example Vagrantfile, now download Calico onto both servers by SSHing onto them and running
```
wget https://github.com/Metaswitch/calico-docker/releases/download/v0.0.7/calicoctl
chmod +x calicoctl
```
Calico has some components that run only on a single host within the cluster. For these instructions, we'll designate core-01 as our "master" node. All the hosts (including the master) will be able to run Calico-networked containers.

Start the master-only Calico components on `core-01`:
```
sudo ./calicoctl master --ip=172.17.8.101
```
Now start the per-host Calico components on all the nodes (only after the master is started):

On core-01:
```
sudo ./calicoctl node --ip=172.17.8.101
```
On core-02:
```
sudo ./calicoctl node --ip=172.17.8.102
```

Various containers should now be running.  `docker ps` should give output like this on the master:
```
core@core-01 ~ $ docker ps
CONTAINER ID        IMAGE                      COMMAND                CREATED             STATUS              PORTS               NAMES
077ceae44fe3        calico/node:v0.0.7     "/sbin/my_init"     About a minute ago   Up About a minute                       calico-node
17a54cc8f88a        calico/master:v0.0.7   "/sbin/my_init"     35 minutes ago       Up 35 minutes                           calico-master
```
And like this on the other hosts:
```
core@core-02 ~ $ docker ps
CONTAINER ID        IMAGE                 COMMAND                CREATED             STATUS              PORTS               NAMES
f770a8acbb11        calico/node:v0.0.7   "/sbin/my_init"     About a minute ago   Up About a minute                       calico-node
```

## Routing via Powerstrip

To allow Calico to set up networking automatically during container creation, Docker API calls need to be routed through the `Powerstrip` proxy which is running on port `2377` on each node. The easiest way to do this is to set the environment before running docker commands.

On both hosts run:
```
export DOCKER_HOST=localhost:2377
```

(Note - this export will only persist for your current SSH session)

Later, once you have guest containers and you want to attach to them or to execute a specific command in them, you'll probably need to skip the Powerstrip proxying, such that the `docker attach` or `docker exec` command speaks directly to the Docker daemon; otherwise standard input and output don't flow cleanly to and from the container.  To do that, just prefix the individual relevant command with `DOCKER_HOST=localhost:2375`.

For example, the first `docker exec` command specified below might actually need to be:
```
DOCKER_HOST=localhost:2375 docker exec workload-A ping -c 4 192.168.1.3
```

Also, when attaching, remember to hit Enter a few times to get a prompt, and to use `Ctrl-P,Q` rather than `exit` to get back out of the container but still leave it running.

## Networking for other containers in the cluster

Now you can start any other containers that you want within the cluster, using normal Docker commands.  To get Calico to network them, simply add `-e CALICO_IP=<IP address>` to specify the IP address that you want that container to have.

(By default containers need to be assigned IPs in the `192.168.0.0/16` range. Use `calicoctl` commands to set up different ranges if desired.)

For example:
```
docker run -e CALICO_IP=192.168.1.1 -tid --name node1 busybox
```

So let's go ahead and start a few containers on each host.
On core-01:
```
docker run -e CALICO_IP=192.168.1.1 --name workload-A -tid busybox
docker run -e CALICO_IP=192.168.1.2 --name workload-B -tid busybox
docker run -e CALICO_IP=192.168.1.3 --name workload-C -tid busybox
```
On core-02:
```
docker run -e CALICO_IP=192.168.1.4 --name workload-D -tid busybox
docker run -e CALICO_IP=192.168.1.5 --name workload-E -tid busybox
```

At this point, the containers have not been added to any security groups so they won't be able to communicate with any other containers.

Create some security groups (this can be done on either host)
```
sudo ./calicoctl group add GROUP_A_C_E
sudo ./calicoctl group add GROUP_B
sudo ./calicoctl group add GROUP_D
```

Now add the containers to the security groups (note that `group add` works from any Calico node, but `group addmember` only works from the Calico node where the container is hosted).
On core-01:
```
sudo ./calicoctl group addmember GROUP_A_C_E workload-A
sudo ./calicoctl group addmember GROUP_B  workload-B
sudo ./calicoctl group addmember GROUP_A_C_E workload-C
```

On core-02:
```
sudo ./calicoctl group addmember GROUP_D workload-D
sudo ./calicoctl group addmember GROUP_A_C_E workload-E
```

Now, check that A can ping C (192.168.1.3) and E (192.168.1.5):
```
docker exec workload-A ping -c 4 192.168.1.3
docker exec workload-A ping -c 4 192.168.1.5
```

Also check that A _cannot_ ping B (192.168.1.2) or D (192.168.1.4):
```
docker exec workload-A ping -c 4 192.168.1.2
docker exec workload-A ping -c 4 192.168.1.4
```

B and D are in their own groups so shouldn't be able to ping anyone else.

Finally, to clean everything up (without doing a `vagrant destroy`), you can run
```
sudo ./calicoctl reset
```

## Troubleshooting

### Basic checks
Running `ip route` shows what routes have been programmed. Routes from other hosts should show that they are programmed by BIRD.

If you have rebooted your hosts, then some configuration can get lost. It's best to run a `sudo ./calicoctl reset` and start again.

If your hosts reboot themselves with a message from `locksmithd` your cached CoreOS image is out of date.  Use `vagrant box update` to pull the new version.  I recommend doing a `vagrant destroy; vagrant up` to start from a clean slate afterwards.

If you hit issues, please raise tickets. Diags can be collected with the `sudo ./calicoctl diags` command.
