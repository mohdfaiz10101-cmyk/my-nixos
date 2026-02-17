{ config, pkgs, ... }: {
  # 自动挂载 4T 硬盘 (DE22...)
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/DE22F5F022F5CD91";
    fsType = "ntfs3";
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" ];
  };
}
