with (import (import ./nixpkgs.nix) {}).lib;
{
  ## DO NOT CHANGE THIS
  format = "1.0.0";
  ## unless you made an automated or manual update
  ## to another supported format.

  ## The attribute to build, either from nixpkgs
  ## of from the overlays located in `.nix/coq-overlays`
  attribute = "coq";
  shell-attribute = "coq-shell";
  src = ../coq-shell;

  ## select an entry to build in the following `bundles` set
  ## defaults to "default"
  default-bundle = "8.18";

  ## write one `bundles.name` attribute set per
  ## alternative configuration, the can be used to
  ## compute several ci jobs as well
  bundles = (genAttrs [ "8.10" "8.11" "8.12" "8.13" "8.14" "8.15" "8.16" "8.17" "8.18" "8.19" ]
    (v: {
      coqPackages.coq.override.version = v;
    })) // {
    master = {
      coqPackages.coq.override.version = "master";
      coqPackages.heq.job = false;
    };
    "8.16-mathcomp2" = {
      coqPackages.coq.override.version = "8.16";
      coqPackages.mathcomp.override.version = "2.1.0";
    };
    "8.17-mathcomp2" = {
      coqPackages.coq.override.version = "8.17";
      coqPackages.mathcomp.override.version = "2.1.0";
    };
    "8.18-mathcomp2" = {
      coqPackages.coq.override.version = "8.18";
      coqPackages.mathcomp.override.version = "2.1.0";
    };
  };

  cachix.coq = {};
  cachix.math-comp = {};
  cachix.coq-community.authToken = "CACHIX_AUTH_TOKEN";
}
