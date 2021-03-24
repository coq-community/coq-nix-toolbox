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
  tasks = let
      mk-tasks = pre: x:
        setAttrByPath pre (mapAttrs (n: v: {override.version = v;}) x);
    in mapAttrs
    (_: i: foldl recursiveUpdate {} [
      (setAttrByPath config.shell-ppath
        { override.version = "${config.src}";
          job = config.shell-attribute;
          main-job = true; })
      (setAttrByPath config.ppath
        { override.version = "${config.src}";
          job = config.attribute;
          main-job = true; })
      i
      (mk-tasks [ "coqPackages" ] override)
      (mk-tasks [ "ocamlPackages" ] ocaml-override)
      (mk-tasks [ ] global-override)
    ]) config.tasks;

  buildInputFrom = pkgs: str:
    pkgs.coqPackages.${str} or pkgs.ocamlPackages.${str} or pkgs.${str};

  mk-instance = taskName: task: let
    overlays = import ./overlays.nix
      { inherit lib overlays-dir coq-overlays-dir ocaml-overlays-dir task;
        inherit (config) attribute pname shell-attribute shell-pname src; };

    pkgs = import config.nixpkgs { inherit overlays; };

    ci = import ./ci.nix { inherit lib this-shell-pkg pkgs task; };

    genCI = import ../deps.nix
      { inherit lib; inherit (pkgs) coqPackages; };
    jsonPkgsDeps = toJSON genCI.pkgsDeps;
    jsonPkgsRevDeps = toJSON genCI.pkgsRevDeps;
    jsonPkgsSorted = toJSON genCI.pkgsSorted;

    inherit (import ../action.nix { inherit lib; }) mkJobs mkAction;
    action = mkAction {
      inherit (config) cachix;
      tasks = taskName;
      jobs = let
          jdeps = genAttrs ci.mains (n: genCI.pkgsRevDepsSet.${n} or {});
        in
        attrNames (removeAttrs
          (jdeps // genAttrs ci.jobs (_: true)
          // foldAttrs (_: _: true) true (attrValues jdeps))
          ci.excluded);
      deps = genCI.pkgsDeps;
    };
    jsonAction = toJSON action;

    patchBIPkg = pkg:
      let bi = map (buildInputFrom pkgs) (config.buildInputs or []); in
      if bi == [] then pkg else
      pkg.overrideAttrs (o: { buildInputs = o.buildInputs ++ bi;});

    notfound-ppath = throw "config-parser-1.0.0: not found: ${config.ppath}";
    notfound-shell-ppath = throw "config-parser-1.0.0: not found: ${config.shell-ppath}";
    this-pkg = patchBIPkg (attrByPath config.ppath notfound-ppath pkgs);
    this-shell-pkg = patchBIPkg (attrByPath config.shell-ppath notfound-shell-ppath pkgs);

    in rec {
      inherit task pkgs this-pkg this-shell-pkg ci genCI;
      inherit jsonPkgsDeps jsonPkgsSorted jsonPkgsRevDeps;
      inherit action jsonAction;
      jsonTask = toJSON task;
    };
  in
{
  instances = mapAttrs mk-instance tasks;
  inherit tasks config;
}
