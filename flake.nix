{
  description = "Charlie's Tony Snowflake System - Minimal Base";

  inputs = {
    # 核心系统源
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.charlie = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        # 注意：这里也需要去你的 configuration.nix 里暂时注释掉关于 flatpak 的配置
      ];
    };
  };
}