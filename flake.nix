{
  description = "Charlie's Tony Snowflake System";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/5d5640599a0050b994330328b9fd45709c909720";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    plasma-manager.url = "github:nix-community/plasma-manager/a524a6160e6df89f7673ba293cf7d78b559eb1a5";
    plasma-manager.inputs.nixpkgs.follows = "nixpkgs";
    plasma-manager.inputs.home-manager.follows = "home-manager";
  };

  outputs = { self, nixpkgs, nix-index-database, disko, sops-nix, home-manager, plasma-manager, ... }@inputs: {
    nixosConfigurations.charlie = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./modules/sshd-permanent.nix
        # 微信 UOS overlay（提取到 packages/wechat-uos.nix）
        { nixpkgs.overlays = [ (import ./packages/wechat-uos.nix) ]; }
        ./configuration.nix
        ./modules/services/litellm-docker.nix
        nix-index-database.nixosModules.nix-index
        { programs.nix-index-database.comma.enable = true; }
        sops-nix.nixosModules.sops
        # home-manager + plasma-manager：声明式固化用户配置（任务栏等）
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.charlie = import ./home/charlie.nix;
        }
      ];
    };

    # minipc — 远程安装用（nixos-anywhere + disko）
    nixosConfigurations.minipc = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./modules/sshd-permanent.nix
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./hosts/minipc/configuration.nix
      ];
    };
  };
}
