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
let config = import ./normalize.nix { inherit (initial) lib config nixpkgs; };
in with config; let

  # preparing medleys
  overriden-medleys = let
      mk-medleys = pre: x:
        setAttrByPath pre (mapAttrs (n: v: {override.version = v;}) x);
    in mapAttrs
    (_: i: foldl recursiveUpdate {} [
      (setAttrByPath shell-ppath
        { override.version = "${src}"; ci = "shell"; })
      (setAttrByPath ppath { override.version = "${src}"; ci = 0; })
      i
      (mk-medleys [ "coqPackages" ] override)
      (mk-medleys [ "ocamlPackages" ] ocaml-override)
      (mk-medleys [ ] global-override)
    ]) config.medleys;

  mk-instance = medley: let
    overlays = import ./overlays.nix
      { inherit lib overlays-dir coq-overlays-dir ocaml-overlays-dir medley; };
    pkgs = import config.nixpkgs { inherit overlays; };
    ci = import ./ci.nix { inherit lib this-shell-pkg pkgs medley; };
    this-pkg = attrByPath config.ppath default-coq-derivation pkgs;
    this-shell-pkg = attrByPath config.shell-ppath default-coq-derivation pkgs;
    in rec {
      inherit medley pkgs this-pkg this-shell-pkg ci;
      jsonMedley = toJSON medley;
    };
  in
{
  instances = mapAttrs (_: mk-instance) overriden-medleys;
  fixed-medley = overriden-medleys;
  inherit config;
}
