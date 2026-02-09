{
  description = "funky-formatter";

  inputs = {
    nixpkgs.url = "github:dkuettel/nixpkgs/stable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        jqJsonFormat = pkgs.writeScriptBin "jq-json-format" ''
          #!${pkgs.zsh}/bin/zsh
          set -eu -o pipefail

          local before=`jq --stream . $1`
          local after=`jq . $1 | jq --stream .`

          if [[ $before == $after ]]; then
            jq . $1
          else
            echo 'Json file probably contains duplicates.' >&2
            exit 1
          fi
        '';
      in
      {
        packages.default = pkgs.buildEnv {
          name = "funky-formatter";
          paths = [ jqJsonFormat ];
        };
      }
    );
}
