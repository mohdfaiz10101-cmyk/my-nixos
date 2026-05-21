{ config, pkgs, lib, ... }:
{
  # --- 音频修复：ALC897 需要 model hint ---
  boot.extraModprobeConfig = ''
    options snd-hda-intel model=generic
  '';

  # --- ydotool 文字输入守护进程（Voxtype 依赖）---
  programs.ydotool.enable = true;

  # --- PipeWire 库路径全局暴露（修复 Chrome Qt multimedia 警告）---
  # 根因：Chrome 内置 Qt 组件找不到 libpipewire-0.3.so
  # 解决：通过 LD_LIBRARY_PATH 让所有进程可见 PipeWire 库
  environment.variables.LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.pipewire ];
}
