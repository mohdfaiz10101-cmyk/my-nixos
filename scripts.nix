{ config, pkgs, ... }:
let
  # 三机位垂直对齐脚本 (已处理 Nix 语法转义)
  scrcpy-layout = pkgs.writeShellScriptBin "scrcpy-layout" ''
    DEVICES=($(${pkgs.android-tools}/bin/adb devices | grep -v "List" | awk '{print $1}'))
    for i in "''${!DEVICES[@]}"; do
      OFFSET=$((i * 450))
      ${pkgs.scrcpy}/bin/scrcpy -s "''${DEVICES[$i]}" \
        --window-title "Phone_$i" \
        --window-x $OFFSET --window-y 100 \
        --window-width 400 --always-on-top &
    done
  '';

  # 一键同步维护脚本
  nx-apply = pkgs.writeShellScriptBin "nx-apply" ''
    cd /etc/nixos
    sudo chown -R charlie:users .
    git add .
    sudo nixos-rebuild switch --flake .#charlie --impure
  '';
in
{
  environment.systemPackages = [ scrcpy-layout nx-apply ];
}