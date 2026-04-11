# Docker 容器 NAT 转发修复
# 问题：Docker bridge 默认 enable_ip_masquerade=false 导致容器无外网访问
# 解决：手动添加 iptables NAT 规则

{ config, lib, pkgs, ... }:

{
  # Docker 容器网络 NAT 转发规则
  networking.firewall.extraCommands = ''
    # 获取默认出口网卡
    OUTIF=$(${pkgs.iproute2}/bin/ip route get 8.8.8.8 | grep -oP 'dev \K\S+')
    
    # 为 Docker 网络添加 NAT 转发
    iptables -t nat -A POSTROUTING -s 172.17.0.0/16 -o $OUTIF -j MASQUERADE  # docker0
    iptables -t nat -A POSTROUTING -s 172.18.0.0/16 -o $OUTIF -j MASQUERADE  # custom networks
    iptables -t nat -A POSTROUTING -s 172.19.0.0/16 -o $OUTIF -j MASQUERADE  # litellm_default
  '';
}
