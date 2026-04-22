{ inputs, pkgs, ... }:
{
  imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

  home.username = "charlie";
  home.homeDirectory = "/home/charlie";
  home.stateVersion = "25.05";

  # ── KDE Plasma 任务栏声明式固化 ──────────────────────────────
  # 防止每次开机/rebuild 后任务栏丢失，固定 launchers 使用 applications: 协议
  # 避免 /nix/store/xxx 硬编码路径（rebuild 后路径变更导致图标消失）
  programs.plasma = {
    enable = true;

    panels = [
      {
        location = "bottom";
        height = 44;
        widgets = [
          "org.kde.plasma.kickoff"
          {
            name = "org.kde.plasma.icontasks";
            config.General = {
              launchers = builtins.concatStringsSep "," [
                "applications:org.kde.konsole.desktop"
                "applications:com.mitchellh.ghostty.desktop"
                "applications:floorp.desktop"
                "applications:org.remmina.Remmina.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:obsidian.desktop"
              ];
              iconSize = "3";
              iconSpacing = "1";
            };
          }
          "org.kde.plasma.marginsseparator"
          {
            name = "org.kde.plasma.systemtray";
            config.General = {
              extraItems = builtins.concatStringsSep "," [
                "org.kde.plasma.clipboard"
                "org.kde.plasma.manage-inputmethod"
                "org.kde.plasma.devicenotifier"
                "org.kde.plasma.notifications"
                "org.kde.plasma.volume"
                "org.kde.plasma.networkmanagement"
                "org.kde.plasma.keyboardlayout"
                "org.kde.kscreen"
                "org.kde.plasma.brightness"
                "org.kde.plasma.battery"
                "org.kde.plasma.mediacontroller"
              ];
            };
          }
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];
  };
}
