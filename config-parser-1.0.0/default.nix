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
  ci-platform,
  lib,
}@initial:
with lib;
let config = import ./normalize.nix
  { inherit (initial) src lib config nixpkgs; };
in with config; let

  # preparing bundles
  bundles = let
      mk-bundles = pre: x:
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
      (mk-bundles [ "coqPackages" ] override)
      (mk-bundles [ "ocamlPackages" ] ocaml-override)
      (mk-bundles [ ] global-override)
    ]) config.bundles;

  buildInputFrom = pkgs: str:
    pkgs.coqPackages.${str} or pkgs.ocamlPackages.${str} or pkgs.${str};

  mk-instance = bundleName: bundle: let
    overlays = import ./overlays.nix
      { inherit lib overlays-dir coq-overlays-dir ocaml-overlays-dir bundle;
        inherit (config) attribute pname shell-attribute shell-pname src; };

    pkgs = import config.nixpkgs { inherit overlays; };

    ci = import ./ci.nix { inherit lib this-shell-pkg pkgs bundle; };

    genCI = import ../deps.nix
      { inherit lib; inherit (pkgs) coqPackages; };
    jsonPkgsDeps = toJSON genCI.pkgsDeps;
    jsonPkgsRevDeps = toJSON genCI.pkgsRevDeps;
    jsonPkgsSorted = toJSON genCI.pkgsSorted;

    inherit (import ../action.nix { inherit lib; }) mkJobs mkAction;
    action = mkAction {
      inherit (config) cachix;
      inherit ci-platform;
      bundles = bundleName;
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
    jsonActionFile = pkgs.writeTextFile {
      name = "jsonAction";
      text = jsonAction;
    };

    patchBIPkg = pkg:
      let bi = map (buildInputFrom pkgs) (config.buildInputs or []); in
      if bi == [] then pkg else
      pkg.overrideAttrs (o: { buildInputs = o.buildInputs ++ bi;});

    notfound-ppath = throw "config-parser-1.0.0: not found: ${toString config.ppath}";
    notfound-shell-ppath = throw "config-parser-1.0.0: not found: ${toString config.shell-ppath}";
    this-pkg = patchBIPkg (attrByPath config.ppath notfound-ppath pkgs);
    this-shell-pkg = patchBIPkg (attrByPath config.shell-ppath notfound-shell-ppath pkgs);

    in rec {
      inherit bundle pkgs this-pkg this-shell-pkg ci genCI;
      inherit jsonPkgsDeps jsonPkgsSorted jsonPkgsRevDeps;
      inherit action jsonAction jsonActionFile;
      jsonBundle = toJSON bundle;
    };
  in
{
  instances = mapAttrs mk-instance bundles;
  inherit bundles config;
}
