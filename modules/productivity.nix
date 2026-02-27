{ config, pkgs, lib, ... }: {

  # --- 1. 軟體矩陣容錯 ---
  environment.systemPackages = let
    pkgNames = [ "utools" "uTools" "utools-bin" ];
    foundPkg = lib.findFirst (name: builtins.hasAttr name pkgs) null pkgNames;
  in if foundPkg != null then [ pkgs.${foundPkg} ] else [ pkgs.appimage-run pkgs.wget ];

}