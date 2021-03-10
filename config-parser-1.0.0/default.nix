# This file is a toolbox file to parse a ./nix/config.nix
# file in format 1.0.0
with builtins;
{ config, # in format 1.0.0
  nixpkgs, # source directory for nixpkgs to provide overlays
  pkgs ? import ../nixpkgs {}, # some instance of pkgs for libraries
  src ? ./., # the source directory
  overlays-dir,
  coq-overlays-dir,
  ocaml-overlays-dir,
  override ? {},
  ocaml-override ? {},
  global-override ? {},
  lib,
}@initial:
with lib;
let
  config = import ./normalize.nix
    { inherit (initial) lib config nixpkgs; };
  mk-overlays = path: callPackage:
    if !pathExists path then {}
    else mapAttrs (x: _v: callPackage (path + "/${x}") {}) (readDir path);
    # preparing inputs
  inputs = let
      mk-inputs = pre: x:
        setAttrByPath pre (mapAttrs (n: v: {override.version = v;}) x);
    in mapAttrs
    (_: i: foldl recursiveUpdate {} [
      (setAttrByPath shell-ppath
        { override.version = "${src}"; ci = "shell"; })
      (setAttrByPath ppath { override.version = "${src}"; ci = 0; })
      i
      (mk-inputs [ "coqPackages" ] override)
      (mk-inputs [ "ocamlPackages" ] ocaml-override)
      (mk-inputs [ ] global-override)
    ]) config.inputs;
  do-override = pkg: cfg:
    let pkg' = if cfg?override
        then pkg.override or (x: pkg) cfg.override else pkg; in
      if cfg?overrideAttrs
      then pkg'.overrideAttrs cfg.overrideAttrs else pkg';
  mk-instance = input: let
    nixpkgs-overrides =
      self: super: mapAttrs (n: ov: do-override super.${n} ov)
        (removeAttrs input [ "coqPackages" "ocamlPackages" ]);
    ocaml-overrides =
      self: super: mapAttrs (n: ov: do-override super.${n} ov)
        (input.ocamlPackages or {});
    coq-overrides =
      self: super: mapAttrs
        (n: ov: do-override (super.${n} or
          (makeOverridable self.mkCoqDerivation {
            pname = "${n}"; version = "${src}";
          })) ov)
        (input.coqPackages or {});
    fold-override = foldl (fpkg: override: fpkg.overrideScope' override);
    overlays = [
      (self: super: mk-overlays overlays-dir self.callPackage)
      nixpkgs-overrides
      (self: super: { coqPackages = fold-override super.coqPackages ([
        (self: super: mk-overlays coq-overlays-dir self.callPackage)
        coq-overrides
        (self: super: { coq = super.coq.override {
          customOCamlPackages = fold-override super.coq.ocamlPackages [
            (self: super: mk-overlays ocaml-overlays-dir self.callPackage)
            ocaml-overrides
          ];};})
      ]);})
      (self: super: { coqPackages =
        super.coqPackages.filterPackages
          (! (super.coqPackages.coq.dontFilter or false)); })
    ];
    pkgs = import config.nixpkgs { inherit overlays; };
    to-step = n: switch n [
      { case = -1;        out = "dependencies";}
      { case = "step--1"; out = "dependencies";}
      { case = "deps";    out = "dependencies";}
      { case = 0;         out = "main";}
      { case = "step-0";  out = "main";}
      { case = true ;     out = "all"; }
      { case = null;      out = "all"; }
      { case = false;     out = "NOCI"; }
      { case = isInt;     out = "step-${toString n}";}
      { case = isString;  out = n;}
      ] (throw "Step is not a string or an int ${toString n}");
    ci-coqpkgs = step: attrValues (filterAttrs (n: v:
          let step-n = to-step (input.coqPackages.${n}.ci.step or false); in
          (step-n != "NOCI") && ((step == step-n) || step == "all"))
      pkgs.coqPackages);
  in
    rec {
      inherit input pkgs;
      default-coq-derivation =
        makeOverridable pkgs.coqPackages.mkCoqDerivation
          { inherit (config) pname; version = "${src}"; };
      this-pkg = attrByPath config.ppath default-coq-derivation pkgs;
      this-shell-pkg = attrByPath config.shell-ppath default-coq-derivation pkgs;
      emacs = with pkgs; emacsWithPackages
        (epkgs: with epkgs.melpaStablePackages; [ proof-general ]);
      ci-pkgs = raw-step: let step = to-step raw-step; in
        switch step [
          { case = "dependencies";
            out = (this-shell-pkg.nativeBuildInputs or []) ++
                  (this-shell-pkg.buildInputs or []) ++
                  (this-shell-pkg.propagatedBuildInputs or []) ++
                  ci-coqpkgs step; }
        ] (ci-coqpkgs step);
      jsonInput = toJSON input;
    };
in
{
  instances = mapAttrs (_: mk-instance) config.inputs;
  fixed-input = config.inputs;
  inherit config;
}
