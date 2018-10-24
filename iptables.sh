#!/bin/bash

IPT="/sbin/iptables"

LOCAL_NET="192.168.0.0/24"

SSH=22
FTP=20,21
DNS=53
SMTP=25,465,587
POP3=110,995
IMAP=143,993
HTTP=80,443
IDENT=113
NTP=123
MYSQL=3306
NET_BIOS=135,137,138,139,445
DHCP=67,68

# Remove all rules
$IPT -F
$IPT -F -t nat
$IPT -F -t mangle
$IPT -X
$IPT -X -t nat
$IPT -X -t mangle

$IPT -P INPUT   ACCEPT
$IPT -P OUTPUT  ACCEPT
$IPT -P FORWARD ACCEPT
$IPT -t nat     -P PREROUTING   ACCEPT
$IPT -t nat     -P OUTPUT       ACCEPT
$IPT -t nat     -P POSTROUTING  ACCEPT
$IPT -t mangle  -P PREROUTING   ACCEPT
$IPT -t mangle  -P OUTPUT       ACCEPT

if [ "$1" = "stop"] then
    echo "iptables stopped!"
    exit 0
fi

$IPT -A INPUT   -i lo   -j ACCEPT
$IPT -A OUTPUT  -o lo   -j ACCEPT

$IPT -P INPUT   DROP
$IPT -P OUTPUT  ACCEPT
$IPT -P FORWARD ACCEPT

if [ "$LOCAL_NET" ]
then
	iptables -A INPUT -s $LOCAL_NET -j ACCEPT
fi

$IPT -A INPUT   -m state --state INVALID -j DROP
$IPT -A FORWARD -m state --state INVALID -j DROP
$IPT -A OUTPUT  -m state --state INVALID -j DROP

###########################################################
# Stealth Scan
###########################################################
$IPT -N STEALTH_SCAN
# iptables -A STEALTH_SCAN -j LOG --log-prefix "stealth_scan_attack: "
$IPT -A STEALTH_SCAN -j DROP

$IPT -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j STEALTH_SCAN

# NULL Scan
$IPT -A INPUT -p tcp --tcp-flags ALL NONE -j STEALTH_SCAN

$IPT -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN         -j STEALTH_SCAN
$IPT -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST         -j STEALTH_SCAN

# Xmas Tree 
$IPT -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# Another Xmas Tree 
$IPT -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j STEALTH_SCAN

$IPT -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j STEALTH_SCAN
$IPT -A INPUT -p tcp --tcp-flags ACK,FIN FIN     -j STEALTH_SCAN
$IPT -A INPUT -p tcp --tcp-flags ACK,PSH PSH     -j STEALTH_SCAN
$IPT -A INPUT -p tcp --tcp-flags ACK,URG URG     -j STEALTH_SCAN

###########################################################
# Fragment Attack
###########################################################
$IPT -A INPUT -f -j DROP

###########################################################
# Ping of Death
###########################################################
$IPT -N PING_OF_DEATH
$IPT -A PING_OF_DEATH -p icmp --icmp-type echo-request \
     -m hashlimit \
     --hashlimit 1/s \
     --hashlimit-burst 10 \
     --hashlimit-htable-expire 300000 \
     --hashlimit-mode srcip \
     --hashlimit-name t_PING_OF_DEATH \
     -j RETURN

# iptables -A PING_OF_DEATH -j LOG --log-prefix "ping_of_death_attack: "
$IPT -A PING_OF_DEATH -j DROP

$IPT -A INPUT -p icmp --icmp-type echo-request -j PING_OF_DEATH

###########################################################
# SYN Flood Attack
###########################################################
$IPT -N SYN_FLOOD
$IPT -A SYN_FLOOD -p tcp --syn \
     -m hashlimit \
     --hashlimit 200/s \
     --hashlimit-burst 30 \
     --hashlimit-htable-expire 300000 \
     --hashlimit-mode srcip \
     --hashlimit-name t_SYN_FLOOD \
     -j RETURN

#iptables -A SYN_FLOOD -j LOG --log-prefix "syn_flood_attack: "
$IPT -A SYN_FLOOD -j DROP

$IPT -A INPUT -p tcp --syn -j SYN_FLOOD

###########################################################
# HTTP DoS/DDoS Attack
###########################################################
$IPT -N HTTP_DOS
$IPT -A HTTP_DOS -p tcp -m multiport --dports $HTTP \
     -m hashlimit \
     --hashlimit 20/s \
     --hashlimit-burst 100 \
     --hashlimit-htable-expire 300000 \
     --hashlimit-mode srcip \
     --hashlimit-name t_HTTP_DOS \
     -j RETURN

#iptables -A HTTP_DOS -j LOG --log-prefix "http_dos_attack: "
$IPT -A HTTP_DOS -j DROP

$IPT -A INPUT -p tcp -m multiport --dports $HTTP -j HTTP_DOS

###########################################################
# SSH Brute Force
###########################################################
$IPT -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --set
$IPT -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 6 -j LOG --log-prefix "ssh_brute_force: "
$IPT -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 6 -j REJECT --reject-with tcp-reset

# HTTP, HTTPS
$IPT -A INPUT -p tcp -m multiport --dports $HTTP -j ACCEPT

# SSH
$IPT -A INPUT -p tcp -m multiport --dports $SSH -j ACCEPT
