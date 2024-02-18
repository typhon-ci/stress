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
      imports = [
        typhon.nixosModules.default
        "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
      ];

      virtualisation = {
        diskSize = 2048;
        memorySize = 2048;
      };

      nix = {
        package = pkgs.nixVersions.nix_2_18;
        settings.experimental-features = ["nix-command" "flakes"];
      };

      services.typhon = {
        enable = true;
        hashedPasswordFile = builtins.toString (pkgs.runCommand "password" {} ''
          echo -n "password" | ${pkgs.libargon2}/bin/argon2 "Guérande" -id -e > $out
        '');
      };

      users.users.root = {
        initialPassword = "root";
        packages = [
          (pkgs.writeShellApplication {
            name = "stress";
            runtimeInputs = [pkgs.jq];
            text = let
              curl = "curl -sf -H 'password: password'";
            in ''
              api="http://localhost:3000/api"

              ${curl} --json '{"flake": true, "url": "github:typhon-ci/stress"}' "$api/projects/stress/create"

              ${curl} -X POST "$api/projects/stress/refresh"
              while [ "$(${curl} "$api/projects/stress" | jq '.last_refresh.Success')" == "null" ]
              do
                  sleep 1
              done

              ${curl} -X POST "$api/projects/stress/update_jobsets"
              while [ "$(${curl} "$api/projects/stress" | jq '.jobsets | length')" == "0" ]
              do
                  sleep 1
              done

              jobsets=$(${curl} "$api/projects/stress" | jq -r '.jobsets | .[] | @uri')
              for jobset in $jobsets
              do
                  ${curl} -X POST "$api/projects/stress/jobsets/$jobset/evaluate"
              done
            '';
          })
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
    typhonProject = typhon.lib.builders.mkProject {
      actions.jobsets = typhon.lib.git.mkJobsets {
        url = "https://github.com/typhon-ci/typhon";
      };
    };
  };
}
