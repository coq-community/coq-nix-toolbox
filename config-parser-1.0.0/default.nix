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

  bundle-ppath = bundle:
    let
      rocq-coq-packages =
        if bundle ? isRocq then "rocqPackages" else "coqPackages";
      path-to-attribute = config.path-to-attribute or [ rocq-coq-packages ];
      path-to-shell-attribute =
        config.path-to-shell-attribute
        or (config.path-to-attribute or [ "coqPackages" ]);
      attribute =
        if bundle ? isRocq && config.attribute == "coq" then "rocq-core"
        else config.attribute;
      shell-attribute =
        if bundle ? isRocq && config.shell-attribute == "coq-shell" then "rocq-shell"
        else config.shell-attribute;
    in {
      inherit rocq-coq-packages attribute shell-attribute;
      # not configurable from config.nix:
      ppath = path-to-attribute ++ [ attribute ];
      shell-ppath = path-to-shell-attribute ++ [ shell-attribute ];
    };

  # preparing bundles
  bundles = let
      mk-bundles = pre: x:
        setAttrByPath pre (mapAttrs (n: v: {override.version = v;}) x);
    in mapAttrs
    (_: i:
      let config-ppath = bundle-ppath i; in
      foldl recursiveUpdate {} [
      (setAttrByPath config-ppath.shell-ppath
        { override.version = "${config.src}";
          job = config-ppath.shell-attribute;
          main-job = true; })
      (setAttrByPath config-ppath.ppath
        { override.version = "${config.src}";
          job = config-ppath.attribute;
          main-job = true; })
      i
      (mk-bundles [ config-ppath.rocq-coq-packages ] override)
      (mk-bundles [ "ocamlPackages" ] ocaml-override)
      (mk-bundles [ ] global-override)
    ]) config.bundles;

  buildInputFrom = pkgs: str:
    pkgs.rocqPackages.${str} or pkgs.coqPackages.${str} or pkgs.ocamlPackages.${str} or pkgs.${str};

  mk-instance = bundleName: bundle: let
    overlays = import ./overlays.nix
      { inherit lib overlays-dir coq-overlays-dir ocaml-overlays-dir bundle;
        inherit (config) attribute pname shell-attribute shell-pname src; };

    pkgs = import config.nixpkgs { inherit overlays; };

    ci = import ./ci.nix { inherit lib this-shell-pkg pkgs bundle; };

    genCI = import ../deps.nix
      { inherit lib; coqPackages =
        if bundle ? isRocq then pkgs.rocqPackages else pkgs.coqPackages; };
    jsonPkgsDeps = toJSON genCI.pkgsDeps;
    jsonPkgsRevDeps = toJSON genCI.pkgsRevDeps;
    jsonPkgsSorted = toJSON genCI.pkgsSorted;

    inherit (import ../action.nix { inherit lib; }) mkJobs mkAction;
    action = mkAction {
      inherit (config) cachix;
      bundles = bundleName;
      jobs = let
          jdeps = genAttrs ci.mains (n: genCI.pkgsRevDepsSet.${n} or {});
        in
        attrNames (removeAttrs
          (jdeps // genAttrs ci.jobs (_: true)
          // foldAttrs (_: _: true) true (attrValues jdeps))
          ci.excluded);
      deps = genCI.pkgsDeps;
    } {
      push-branches = bundle.push-branches or [ "master" ];
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

    config-ppath = bundle-ppath bundle;
    notfound-ppath = throw "config-parser-1.0.0: not found: ${toString config-ppath.ppath}";
    notfound-shell-ppath = throw "config-parser-1.0.0: not found: ${toString config-ppath.shell-ppath}";
    this-pkg = patchBIPkg (attrByPath config-ppath.ppath notfound-ppath pkgs);
    this-shell-pkg = patchBIPkg (attrByPath config-ppath.shell-ppath notfound-shell-ppath pkgs);

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
