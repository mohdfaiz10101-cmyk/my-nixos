{ config, pkgs, lib, ... }:
{
  # --- NVIDIA RTX 3060 Ti 驅動 ---
  hardware.graphics.enable = true;
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Vulkan 使用 NVIDIA GPU（修复 Zed 等 Vulkan 应用检测 llvmpipe 问题）
  environment.variables.VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";

  # --- 桌面環境：KDE Plasma + SDDM（自動登入）---
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.sddm.settings.General.Numlock = "on";
  services.displayManager.defaultSession = "plasma";
  services.displayManager.autoLogin = {
    enable = true;
    user = "charlie";
  };
  services.desktopManager.plasma6.enable = true;
  # services.desktopManager.cosmic.enable = true; # 上游 cosmic-edit 哈希不匹配，等修复
  # services.displayManager.cosmic-greeter.enable = false;

  # --- Sunshine 远程串流服务器（Moonlight 客户端连接）---
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };

  # --- 鼠標主題：Catppuccin Mocha Dark ---
  environment.variables.XCURSOR_THEME = "catppuccin-mocha-dark-cursors";
  environment.variables.XCURSOR_SIZE = "24";

  # --- Electron 渲染修復（NVIDIA + Wayland）---
  environment.variables.NIXOS_OZONE_WL = "1";
  environment.variables.ELECTRON_OZONE_PLATFORM_HINT = "auto";

  # --- XDG 缓存重定向到池分区（减轻根分区压力）---
  environment.variables.XDG_CACHE_HOME = "/mnt/pool/offload/cache-charlie";
  system.activationScripts.nix-cache-local = {
    text = ''
      POOL_NIX="/mnt/pool/offload/cache-charlie/nix"
      LOCAL_NIX="/home/charlie/.cache/nix"
      mkdir -p "$LOCAL_NIX"
      chown charlie:users "$LOCAL_NIX"
      if [ -d "$POOL_NIX" ] && [ ! -L "$POOL_NIX" ]; then
        cp -an "$POOL_NIX/." "$LOCAL_NIX/" 2>/dev/null || true
        rm -rf "$POOL_NIX" 2>/dev/null || true
      fi
      [ -L "$POOL_NIX" ] || ln -sf "$LOCAL_NIX" "$POOL_NIX"
      chown -h charlie:users "$POOL_NIX"
    '';
    deps = [ "users" ];
  };

  # --- Sunshine 虚拟输入设备权限 ---
  services.udev.extraRules = ''
    ATTR{idVendor}=="0bda", ATTR{idProduct}=="1a2b", RUN+="${pkgs.usb-modeswitch}/bin/usb_modeswitch -v 0x0bda -p 0x1a2b -K 1"
    KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
    KERNEL=="hidraw*", MODE="0660", GROUP="input"
  '';

  # --- fcitx5 環境變量（每窗口記住狀態）---
  environment.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    INPUT_METHOD = "fcitx";
    GLFW_IM_MODULE = "ibus";
  };
  # --- 禁用非必要服务（节省内存）---
  services.geoclue2.enable = lib.mkForce false;
  systemd.services.ModemManager.enable = lib.mkForce false;
}
