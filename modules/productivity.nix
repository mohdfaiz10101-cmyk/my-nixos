{ config, pkgs, lib, ... }:

let
  voxtype = pkgs.stdenv.mkDerivation rec {
    pname = "voxtype";
    version = "0.6.5";

    src = pkgs.fetchurl {
      url = "https://github.com/peteonrails/voxtype/releases/download/v${version}/voxtype-${version}-linux-x86_64-avx2";
      sha256 = "sha256-28QTFbkrLOyDioCwr9G77muSCssXvgUcSDg9k2eP+CQ=";
    };

    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = with pkgs; [ autoPatchelfHook ];
    buildInputs = with pkgs; [
      alsa-lib
      stdenv.cc.cc.lib
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      libGL
    ];

    installPhase = ''
      runHook preInstall
      install -D $src $out/bin/voxtype
      chmod +x $out/bin/voxtype
      runHook postInstall
    '';

    meta = with lib; {
      description = "Voice-to-text with push-to-talk for Wayland";
      homepage = "https://voxtype.io";
      license = licenses.unfree;
      platforms = platforms.linux;
    };
  };
in
{
  # --- 生產力工具 ---
  environment.systemPackages = with pkgs; [
    windsurf        # Windsurf AI IDE
    whisper-cpp     # 語音轉文字（本地 Whisper）
    sox             # 音頻錄製/處理
    appimage-run
    wget
    voxtype         # 語音輸入（Push-to-Talk）
    wtype           # Wayland 文字輸入工具（Voxtype 依賴）
  ];

}
