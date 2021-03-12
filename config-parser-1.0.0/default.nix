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
let config = import ./normalize.nix
  { inherit (initial) src lib config nixpkgs; };
in with config; let

  # preparing tasks
  overriden-tasks = let
      mk-tasks = pre: x:
        setAttrByPath pre (mapAttrs (n: v: {override.version = v;}) x);
    in mapAttrs
    (_: i: foldl recursiveUpdate {} [
      (setAttrByPath shell-ppath
        { override.version = "${config.src}"; ci.job = "shell"; })
      (setAttrByPath ppath { override.version = "${config.src}"; ci.job = "main"; })
      i
      (mk-tasks [ "coqPackages" ] override)
      (mk-tasks [ "ocamlPackages" ] ocaml-override)
      (mk-tasks [ ] global-override)
    ]) config.tasks;

  buildInputFrom = pkgs: str:
    pkgs.coqPackages.${str} or pkgs.ocamlPackages.${str} or pkgs.${str};

  mk-instance = task: let
    overlays = import ./overlays.nix
      { inherit lib overlays-dir coq-overlays-dir ocaml-overlays-dir task; };
    pkgs = import config.nixpkgs { inherit overlays; };
    ci = import ./ci.nix { inherit lib this-shell-pkg pkgs task; };
    patchBIPkg = pkg:
      let bi = map (buildInputFrom pkgs) (config.buildInputs or []); in
      if bi == [] then pkg else
      pkg.overrideAttrs (o: { buildInputs = o.buildInputs ++ bi;});

    this-pkg = patchBIPkg (attrByPath config.ppath default-coq-derivation pkgs);
    this-shell-pkg = patchBIPkg (attrByPath config.shell-ppath default-coq-derivation pkgs);

    in rec {
      inherit task pkgs this-pkg this-shell-pkg ci;
      jsonTask = toJSON task;
    };
  in
{
  instances = mapAttrs (_: mk-instance) overriden-tasks;
  fixed-task = overriden-tasks;
  inherit config;
}
