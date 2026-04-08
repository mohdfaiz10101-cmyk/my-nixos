{ config, pkgs, lib, ... }:
{
  # --- 音频修复：ALC897 需要 model hint ---
  boot.extraModprobeConfig = ''
    options snd-hda-intel model=generic
  '';

  # --- ydotool 文字输入守护进程（Voxtype 依赖）---
  programs.ydotool.enable = true;
}
