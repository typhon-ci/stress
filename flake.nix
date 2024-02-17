{
  inputs = {
    typhon.url = "github:typhon-ci/typhon";
    nixpkgs.follows = "typhon/nixpkgs";
  };

  outputs = {
    self,
    typhon,
    nixpkgs,
  }: let
    configuration = {pkgs, ...}: {
      imports = [typhon.nixosModules.default];

      nix = {
        package = pkgs.nixVersions.nix_2_18;
        settings.experimental-features = ["nix-command" "flakes"];
      };

      services.typhon = {
        enable = true;
        passwordFile = "${pkgs.writeText "password" "password"}";
      };

      services.nginx = {
        enable = true;
        virtualHosts."example.com" = {
          locations."/" = {
            proxyPass = "http://localhost:3000";
            recommendedProxySettings = true;
          };
        };
      };

      users.users.root = {
        initialPassword = "root";
        packages = [
          (pkgs.writeShellScriptBin "stress" ''
            curl -H 'password: password' --json '{"flake":true,"url":"github:typhon-ci/stress"}' http://localhost/api/projects/stress/create
          '')
        ];
      };
    };
    system = "x86_64-linux";
    vm = (import "${nixpkgs}/nixos" {inherit configuration system;}).vm;
    pkgs = import nixpkgs {inherit system;};
  in {
    packages.${system}.default = pkgs.writeShellScriptBin "run" ''
      QEMU_KERNEL_PARAMS=console=ttyS0 ${vm}/bin/run-nixos-vm -nographic; reset
    '';
    typhonProject = typhon.lib.mkProject {
      actions.jobsets = typhon.lib.mkGitJobsets {
        url = "https://github.com/typhon-ci/typhon";
      };
    };
  };
}
