{ pkgs }: with pkgs; [
  # 基础工具
  git
  os-prober
  fastfetch
  
  # 浏览器与通讯
  google-chrome
  firefox
  wechat-uos
  
  # 生产力与开发
  vscode
  scrcpy
  android-tools
  flclash

  # --- 修正后的输入法组件：全量对齐 Qt6 ---
  qt6Packages.fcitx5-chinese-addons
  fcitx5-rime
  qt6Packages.fcitx5-configtool
  qt6Packages.fcitx5-qt
]