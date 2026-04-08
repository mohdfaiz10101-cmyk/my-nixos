{ config, pkgs, lib, ... }:
{
  # --- 基本网络 ---
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # NetworkManager-wait-online 默认等待所有接口就绪（耗时 6.5s），禁用
  systemd.services.NetworkManager-wait-online.enable = false;

  # LAN 固定设备名称解析
  networking.extraHosts = ''
    192.168.2.100 tony nixos
    192.168.2.101 minipc
    192.168.2.36  winpc windows
  '';

  # --- 防火墙 ---
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # --- SSH 服务（Vast.ai GPU 出租必需）---
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      X11Forwarding = false;
    };
    ports = [ 22 ];
  };
}
