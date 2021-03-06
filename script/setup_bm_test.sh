#! /bin/bash
#
# setup_bm_test.sh
# About: Setup bare-mental tests
#        Bare-mental tests are used to evaluate the overhead of OpenStack's
#        virtualized network infrastructure
#        UDP sender and receiver are running in different network namespaces on
#        the same physical node. The network function program is running on
#        another physical node. Veth pairs and OVS are used to connect namespaces
#
#  MARK: - Run this script with sudo
#        - OVS-DPDK should be configured
#

#apt update
#apt install -y openvswitch-switch

#LOCAL_PHY_IFCE="eth1"
LOCAL_PHY_IP="10.0.0.22/24"

# MAC address of the NIC running VNF programs
REMOTE_PHY_MAC="08:00:27:1e:2d:b3"

SEND_IP="10.0.1.10/24"
SEND_HOST="10.0.1.10"
RECV_IP="10.0.1.11/24"
RECV_HOST="10.0.1.11"

# Create two namespaces and veths on one physical node
ip netns add ns1
ip netns add ns2

ip link add veth0-ns1 type veth peer name veth0-root
ip link set veth0-root up
ip link set veth0-ns1 netns ns1
ip netns exec ns1 ip link set veth0-ns1 up
SEND_MAC=$(ip -o netns exec ns1 ip link show veth0-ns1 | grep ether | awk '{print $2}')

ip link add veth1-ns2 type veth peer name veth1-root
ip link set veth1-root up
ip link set veth1-ns2 netns ns2
ip netns exec ns2 ip link set veth1-ns2 up
RECV_MAC=$(ip -o netns exec ns2 ip link show veth1-ns2 | grep ether | awk '{print $2}')

ip netns exec ns1 ip addr add $SEND_IP dev veth0-ns1
ip netns exec ns2 ip addr add $RECV_IP dev veth1-ns2

# Add static ARPs
ip netns exec ns1 arp -s $RECV_HOST $RECV_MAC
ip netns exec ns2 arp -s $SEND_HOST $SEND_MAC

# Turn off checksum offloading of veth pairs
ip netns exec ns1 ethtool --offload veth0-ns1 rx off tx off
ip netns exec ns2 ethtool --offload veth1-ns2 rx off tx off

## Create a OVS (with DPDK) to connect two namespaces and the phy ifce
ovs-vsctl add-br br0 -- set bridge br0 datapath_type=netdev
ovs-vsctl add-port br0 veth0-root -- set Interface veth0-root ofport=1
ovs-vsctl add-port br0 veth1-root -- set Interface veth1-root ofport=2

# MARK: This step will enable DPDK interface, BY DEFAULT 100% will be used.
ovs-vsctl add-port br0 dpdk-p0 -- set Interface dpdk-p0 type=dpdk \
    options:dpdk-devargs=0000:00:09.0

ovs-ofctl mod-port br0 1 no-flood
ovs-ofctl mod-port br0 2 no-flood
ovs-ofctl mod-port br0 3 no-flood

ip addr add $LOCAL_PHY_IP dev br0
ip link set br0 up

ovs-vsctl show

# Add static flow rules
# Keep the IP adress unchanged, modify MAC addresses
ovs-ofctl add-flow br0 "in_port=1 actions=mod_dl_dst:$REMOTE_PHY_MAC,output:3"
ovs-ofctl add-flow br0 "in_port=2 actions=mod_dl_dst:$SEND_MAC,output:1"
ovs-ofctl add-flow br0 "in_port=3 actions=mod_dl_dst:$RECV_MAC,output:2"

ovs-ofctl dump-flows br0

echo "# Setup finished."
echo "    Run UDP sender in namespace ns1 with IP: $SEND_IP"
echo "    Run UDP receiver in namespace ns2 with IP: $RECV_IP"
