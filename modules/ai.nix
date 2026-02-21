{ config, pkgs, inputs, ... }: {
  # 1. Ollama 服務配置 (這部分的 77% 編譯進度會被保留！)
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; 
  };

  # 2. OpenClaw 原生服務整合 (暫時註解以繞過 403 限制與 Hash 報錯)
  # imports = [ 
  #   inputs.openclaw.nixosModules.openclaw-gateway 
  # ];

  # services.openclaw-gateway = {
  #   enable = true;
  #   port = 18789;
  #   package = inputs.openclaw.packages.${pkgs.system}.default;
  # };
}