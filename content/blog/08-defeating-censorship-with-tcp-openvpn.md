---
title: "08 Defeating Censorship And Improviing Security With Openvpn On Port 443"
date: 2019-01-09T10:10:13Z
draft: true
---

# Introduction



# Keypoints
connect to internet via vpn from anywhere
annoyed when vpn is blocked
    how is vpn blocked?
        block 1194/udp?

run openvpn instance on port 443/tcp
https://github.com/Angristan/OpenVPN-install/issues/28
cp openvpn config andm ake a new instance with systemd

systemd magic
    vi /lib/systemd/system/openvpn-server@.service - gives more details
    @. is name - man 5 systemd.service, man 5 systemd.unit

put /etc/openvpn/server/tcp.conf file that has tcp config
systemctl start openvpn-server@tcp - to run tcp instance

connection successful but no internet/ping?
look at bigger picture - nesting vpn tunnels kek

iptables debugging
issue found - local firewall zone...

further work
    check logging? - if connecting via router what ip is being logged where?
    since router port 443 is used for haproxy, how do I run openvpn forwarding on 443?
