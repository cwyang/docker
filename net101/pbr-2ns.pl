#!/usr/bin/perl
#
# 14 Apr 2020
# Chul-Woong Yang
#
# Client (C)         Proxy (P)
# 10.10.1.1/24      10.10.2.1/24
#     veth0             veth0
#      |                 |
#   veth pair         veth pair
#      |                 |
#  -----------(HOST)--------------
# client-veth0       proxy-veth0
# 10.10.1.2/24      10.10.2.2/24
#      |                 |            172.16.202.30
#      +-----------------+-------------- enp4s0 ---- INTERNET
#
# Policy Routing on Host
# [Client->Proxy]
# ip rule:  from 10.10.1.0/24 iif client-veth0 lookup 100
# ip route: (100) default via 10.10.2.1 dev proxy-veth0
# [Proxy->Internet]
# ip route: (master) default via 172.16.202.1 dev enp4s0 proto static metric 100
# iptables: -t nat -A POSTROUTING -s 10.10.10.1/32 -o enp4s0 -j MASQUERADE
# [Internet->Proxy]
# ip rule:  from all to 10.10.1.0/24 iif enp4s0 lookup 100
# ip route: (100) default via 10.10.2.1 dev proxy-veth0
# [Proxy->Client]
# ip rule:  from all to 10.10.1.0/24 iif proxy-veth0 lookup 101
# ip route: (101) default via 10.10.1.1 dev client-veth0

# Problem is, When I ping 8.8.8.8 from Client, within client netns,
#     source ip masquerading does not happen.
#     iptables masquerade rule does not match and defaults to ACCEPT .
#     I expect that tcpdump on enp4s0 shows 172.16.202.30 --> 8.8.8.8,
#     but it shows 10.10.1.1 --> 8.8.8.8
#     When I checked on iptables mangle table, packets flows by given policy:
#   PREROUTING: client-veth0, 10.10.1.1 --> 8.8.8.8
#   POSTROUTING: proxy-veth0, 10.10.1.1 --> 8.8.8.8
#   PREROUTING: proxy-veth0, 10.10.1.1 --> 8.8.8.8
#   POSTROUTING: enp4s0, 10.10.1.1 --> 8.8.8.8
    
    
#  is shown at POSTROUTING
#  Packets are in from client-veth0
    

# 클라이언트가 인터넷을 접근할 때 라우팅을 통해 프락시를 경유하도록 하고 싶다.
# Client와 Proxy를 네트워크 네임스페이스로 분리하여 설정해보자

# client ns를 만들어 veth pair를 만들어 host와 연결한 후 ip를 부여한다.
# client의 veth tunnel간에 forwarding을 해 주기 위해서
# proxy 에도 마찬가지로 진행한다.
#
# https://blogs.igalia.com/dpino/2016/04/10/network-namespaces/

use strict;

my $debug=1;
my $dryrun=0;
my $ip="ip";
my $iptables="iptables";
my $nic_name="veth0";

sub run_cmd {
    my $cmd = shift;
    print "$cmd\n" if ($debug);
    return if ($dryrun);
    my $result = system("$cmd > /dev/null");
    if ($result != 0) {
	print "  Error: ($result) $cmd \n";
    }
}
sub iptables_add {
    my ($target, $line) = @_;
    run_cmd("$iptables -D $target $line");
    run_cmd("$iptables -A $target $line");
}
sub ip {
    my $ns = shift if (@_ >= 2);
    my ($line) = @_;
    my $cmd = $ns ? "$ip netns exec $ns $ip" : "$ip";
    run_cmd("$cmd $line");
}

sub make_ns {
    my ($target, $nsaddr, $hostaddr) = @_;
    my ($host) = split(/\//, $hostaddr);
    
    ip("netns del $target");
    ip("link del $target-$nic_name");
    # create namespace
    ip("netns add $target");
    # create a veth pair
    ip("link add $target-$nic_name type veth peer name $nic_name");
    ip("link set $nic_name netns $target");
    # address setup
    ip("addr add $hostaddr dev $target-$nic_name");
    ip("link set $target-$nic_name up");
    # address setup on target namespace
    ip($target, "addr add $nsaddr dev $nic_name");
    ip($target, "link set $nic_name up");
    ip($target, "link set lo up");
    ip($target, "route add default via $host dev $nic_name");
}

make_ns("client", "10.10.1.1/24", "10.10.1.2/24");
make_ns("proxy",  "10.10.2.1/24", "10.10.2.2/24");
route_setup("10.10.10.0/24");

# Policy Routing 설정
# (src: 10.10.1.0/24 if:client-eth0) 에서 들어오는 트래픽은 gw-proxy (10.10.2.1)로
# (src: 10.10.1.0/24 if:proxy-eth0)  에서 들어오는 트래픽은 source masqurade하여 default route로
# (dst: 10.10.1.0/24 if:proxy-eth0)  에서 들어오는 트래픽은 gw-client (10.10.1.1)로
# (dst: 10.10.1.0/24)                에서 들어오는 트래픽은 gw-proxy  (10.10.2.1)로 

sub route_setup {
    my $net_client = "10.10.1.0/24";
    my $net_proxy  = "10.10.2.0/24";
    my $gw_client = "10.10.1.1";
    my $gw_proxy  = "10.10.2.1";
    my $nic_client="client-veth0";
    my $nic_proxy ="proxy-veth0";
    my $nic_internet="enp4s0";

    # debug
    if ($debug) {
	iptables_add("PREROUTING", "-t raw -j TRACE");
	# we need to do following things like to enable netfliter logging
	# sysctl -w net.netfilter.nf_log_all_netns=1
	# sysctl -w "net.netfilter.nf_log.2"=nf_log_ipv4
    }
    # flush
    ip("route flush table 100");
    ip("route flush table 101");
    # OUTBOUND: src --> proxy
    ip("rule del from $net_client iif $nic_client prio 100 table 100");
    ip("rule add from $net_client iif $nic_client prio 100 table 100");
    # INBOUND: internet --> proxy
    ip("rule del to $net_client iif $nic_internet prio 102 table 100");
    ip("rule add to $net_client iif $nic_internet prio 102 table 100");
    # RT: route to proxy
    ip("route add default via $gw_proxy dev $nic_proxy table 100");

    # OUTBOUND: proxy --> internet
    # proxy --> default route w/ masquerade
    iptables_add("POSTROUTING", "-t nat -s $net_client ! -d $net_client -o $nic_internet -j MASQUERADE");


    # INBOUND: proxy --> client
    ip("rule del to $net_client iif $nic_proxy prio 101 table 101");
    ip("rule add to $net_client iif $nic_proxy prio 101 table 101");
    # RT: route to client
    ip("route add default via $gw_client dev $nic_client table 101");

    # conntrack zone split
    # zone 0: default zone, generic host traffic along proxy and Internet
    # zone 1: client <-> proxy traffic

    iptables_add("PREROUTING", "-t raw -i $nic_client -j CT --zone 1");
    iptables_add("PREROUTING", "-t raw -i $nic_proxy -d $net_client -j CT --zone 1");
}





#
# Host: source ip가 10.10.0/24면 Proxy로
#
