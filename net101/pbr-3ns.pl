#!/usr/bin/perl
#
# 21 Apr 2020
# Chul-Woong Yang
#
# Client (C)         Proxy (P1)      Proxy (P2)
# 10.10.1.1/24      10.10.2.1/24    10.10.3.1/24
#     veth0             veth0          veth0
#      |                 |               |
#   veth pair         veth pair      veth pair
#      |                 |               |
#  -----------(HOST)----------------------------
# client-veth0       p1-veth0          p2-veth0
# 10.10.1.2/24      10.10.2.2/24     10.10.3.2/24
#      |                 |               |    172.16.202.30
#      +-----------------+---------------+------- enp4s0 ---- INTERNET
#
# Policy Routing on Host
# [Client->P1]
# ip rule:  from 10.10.1.0/24 iif client-veth0 lookup 101
# ip route: (101) default via 10.10.2.1 dev p1-veth0
# [P1->P2]
# ip rule:  from 10.10.1.0/24 iif p1-veth0 lookup 102
# ip route: (102) default via 10.10.3.1 dev p2-veth0
# [P2->Internet]
# ip route: (master) default via 172.16.202.1 dev enp4s0 proto static metric 100
# iptables: -t nat -A POSTROUTING -s 10.10.1.1/24 -o enp4s0 -j MASQUERADE
# [Internet->P2]
# ip rule:  from all to 10.10.1.0/24 iif enp4s0 lookup 102
# ip route: (102) default via 10.10.3.1 dev p2-veth0
# [P2->P1]
# ip rule:  from all to 10.10.1.0/24 iif p2-veth0 lookup 101
# ip route: (101) default via 10.10.2.1 dev p1-veth0
# [P1->Client]
# ip rule:  from all to 10.10.1.0/24 iif proxy-veth0 lookup 100
# ip route: (100) default via 10.10.1.1 dev client-veth0

use strict;

my $debug=1;
my $dryrun=1;
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
sub iptables {
    my $arg = shift;
    if ($arg =~ /-A\b/) {
	(my $del_arg = $arg) =~ s/-A\b/-D/;
	run_cmd("$iptables $del_arg");
    }
    run_cmd("$iptables $arg");
}
sub ip {
    my $ns = shift if (@_ >= 3);
    my ($cmd, $arg) = @_;
    my $combined_cmd = $ns ? "$ip netns exec $ns $ip $cmd" : "$ip $cmd";
    if ($cmd eq "rule") {
	my $del_arg = $arg;
	if ($del_arg =~ s/\badd\b/del/) {
	    run_cmd("$combined_cmd $del_arg");
	}
    }
    run_cmd("$combined_cmd $arg");
}
sub make_ns {
    my ($target, $nsaddr, $hostaddr) = @_;
    my ($host) = split(/\//, $hostaddr);
    
    ip("netns", "del $target");
    ip("link", "del $target-$nic_name");
    # create namespace
    ip("netns", "add $target");
    # create a veth pair
    ip("link", "add $target-$nic_name type veth peer name $nic_name");
    ip("link", "set $nic_name netns $target");
    # address setup
    ip("addr", "add $hostaddr dev $target-$nic_name");
    ip("link", "set $target-$nic_name up");
    # address setup on target namespace
    ip($target, "addr", "add $nsaddr dev $nic_name");
    ip($target, "link", "set $nic_name up");
    ip($target, "link", "set lo up");
    ip($target, "route", "add default via $host dev $nic_name");
}
sub route_setup {
    my $net_client = "10.10.1.0/24";
    my $net_p1  = "10.10.2.0/24";
    my $net_p2  = "10.10.3.0/24";
    my $gw_client = "10.10.1.1";
    my $gw_p1  = "10.10.2.1";
    my $gw_p2  = "10.10.3.1";
    my $nic_client="client-veth0";
    my $nic_p1 ="p1-veth0";
    my $nic_p2 ="p2-veth0";
    my $nic_internet="enp4s0";

    if ($debug) {
	# we need to do following things like to enable netfliter logging
	iptables("-A PREROUTING -t raw -j TRACE");
	system "sysctl -w net.netfilter.nf_log_all_netns=1";
	system "sysctl -w net.netfilter.nf_log.2=nf_log_ipv4";
	#	system "sysctl -w net.netfilter.nf_log.2=nfnetlink_log";
    }
    # flush
    for my $i (100..102) {
	ip("route", "flush table $i");
    }
    # OUTBOUND: src --> p1
    ip("rule", "add from $net_client iif $nic_client prio 100 table 101");
    # OUTBOUND: p1 --> p2
    ip("rule", "add from $net_client iif $nic_p1 prio 100 table 102");
    # OUTBOUND: proxy --> internet: default route

    # INBOUND: internet --> p2
    ip("rule", "add to $net_client iif $nic_internet prio 100 table 102");
    # INBOUND: p2 --> p1
    ip("rule", "add to $net_client iif $nic_p2 prio 100 table 101");
    # INBOUND: p1 --> client
    ip("rule", "add to $net_client iif $nic_p1 prio 100 table 100");
    
    # RT: route to client
    ip("route", "add default via $gw_client dev $nic_client table 100");
    # RT: route to p1
    ip("route", "add default via $gw_p1 dev $nic_p1 table 101");
    # RT: route to p2
    ip("route", "add default via $gw_p2 dev $nic_p2 table 102");

    # NAT
    iptables("-A POSTROUTING -t nat -s $net_client ! -d $net_client -o $nic_internet -j MASQUERADE");

    # conntrack zone split
    # zone 0: default zone, generic host traffic along p2 and Internet
    # zone 1: client <-> p1 traffic
    # zone 2: p1 <-> p2 traffic

    iptables("-A PREROUTING -t raw -i $nic_client -s $net_client -j CT --zone 1");
    iptables("-A PREROUTING -t raw -i $nic_p1 -d $net_client -j CT --zone 1");
    iptables("-A PREROUTING -t raw -i $nic_p1 -s $net_client -j CT --zone 2");
    iptables("-A PREROUTING -t raw -i $nic_p2 -d $net_client -j CT --zone 2");
}

if (1) {
    make_ns("client", "10.10.1.1/24", "10.10.1.2/24");
    make_ns("p1",  "10.10.2.1/24", "10.10.2.2/24");
    make_ns("p2",  "10.10.3.1/24", "10.10.3.2/24");
    route_setup();
}

