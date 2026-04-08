# WeChat UOS 4.1.1 FHS Overlay
#
# Why: 微信 Linux 版需要 FHS 兼容环境，NixOS 非标准文件系统路径
#      需要构建 buildFHSEnv 包装才能正常运行。
# What: 提供 wechat-uos 包，包含 FHS 环境和桌面集成。
# Test: 运行 wechat-uos 命令，确认微信窗口正常启动，输入法可用。
final: prev:
let
  newWechatRaw = prev.stdenvNoCC.mkDerivation {
    pname = "wechat-uos";
    version = "4.1.1";
    src = prev.fetchurl {
      url = "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb";
      hash = "sha256-zmpcIBg5OD1qsBmMAm7OwnS9YoAwRK7GH9yiDgLHl+I=";
      curlOpts = "-A apt";
    };
    nativeBuildInputs = [ prev.dpkg ];
    unpackPhase = ''
      runHook preUnpack
      dpkg -x $src ./wechat-uos
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r wechat-uos/* $out
      runHook postInstall
    '';
  };
in
{
  wechat-uos = prev.buildFHSEnv {
    pname = "wechat-uos";
    version = "4.1.1";
    runScript = prev.writeShellScript "wechat-uos-launcher" ''
      export QT_QPA_PLATFORM=xcb
      export QT_AUTO_SCREEN_SCALE_FACTOR=1
      export LD_LIBRARY_PATH="${
        prev.lib.makeLibraryPath (with prev; [
          stdenv.cc.cc stdenv.cc.libc pango zlib libxcb-wm libxcb-image
          libxcb-keysyms libxcb-render-util libx11 libxt libxext libsm
          libice libxcb libxkbcommon libxshmfence libxi libxft libxcursor
          libxfixes libxscrnsaver libxcomposite libxdamage libxtst libxrandr
          libnotify atk atkmm cairo at-spi2-atk at-spi2-core alsa-lib dbus
          cups gtk3 gdk-pixbuf libexif ffmpeg libva freetype fontconfig
          libxrender libuuid expat glib nss nspr libGL libxml2 pango
          libdrm libgbm vulkan-loader systemd wayland pulseaudio qt6.qt5compat
          bzip2 krb5
        ])
      }"
      if [[ ''${XMODIFIERS} =~ fcitx ]]; then
        export QT_IM_MODULE=fcitx
        export GTK_IM_MODULE=fcitx
      elif [[ ''${XMODIFIERS} =~ ibus ]]; then
        export QT_IM_MODULE=ibus
        export GTK_IM_MODULE=ibus
        export IBUS_USE_PORTAL=1
      fi
      exec ${newWechatRaw.outPath}/opt/wechat/wechat
    '';
    targetPkgs = pkgs: [
      prev.util-linux
      prev.coreutils
      (prev.stdenvNoCC.mkDerivation {
        meta.priority = 1;
        name = "wechat-uos-env";
        buildCommand = ''
          mkdir -p $out/etc $out/usr/bin $out/usr/share $out/opt $out/var
          ln -s ${newWechatRaw.outPath}/opt/* $out/opt/
          ln -s ${prev.util-linux}/bin/lsblk $out/usr/bin/lsblk
        '';
      })
    ];
    extraInstallCommands = ''
      mkdir -p $out/share/applications
      mkdir -p $out/share/icons
      cp -r ${newWechatRaw.outPath}/usr/share/applications/wechat.desktop $out/share/applications/
      if [ -d ${newWechatRaw.outPath}/usr/share/icons ]; then
        cp -r ${newWechatRaw.outPath}/usr/share/icons/* $out/share/icons/
      fi
      substituteInPlace $out/share/applications/wechat.desktop \
        --replace-quiet 'Exec=/usr/bin/wechat' "Exec=$out/bin/wechat-uos --" \
        --replace-quiet 'Exec=wechat' "Exec=$out/bin/wechat-uos --"
      sed -i -e '/\[Desktop Entry\]/a\' -e 'StartupWMClass=wechat' $out/share/applications/wechat.desktop
    '';
    meta = {
      description = "Messaging app";
      homepage = "https://weixin.qq.com/";
      license = prev.lib.licenses.unfree;
      platforms = [ "x86_64-linux" ];
      mainProgram = "wechat-uos";
    };
  };
}
