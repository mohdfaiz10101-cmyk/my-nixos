{ config, pkgs, lib, ... }: {

  # --- 生產力工具 ---
  environment.systemPackages = with pkgs; [
    windsurf        # Windsurf AI IDE
    whisper-cpp     # 語音轉文字（本地 Whisper）
    sox             # 音頻錄製/處理
    appimage-run
    wget
  ];

}
