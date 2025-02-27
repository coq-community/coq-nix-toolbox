# This file is a toolbox file to parse a ./nix/config.nix
# file in format 1.0.0
{lib, config, nixpkgs, src}@initial:
with builtins; with lib;
let
  normalize-coqpkg = name: pkg: let j = pkg.job or name; in
    pkg // { job = switch j [
               { case = true;     out = name; }
               { case = false;    out = "_excluded"; }
               { case = isString; out = j; }
             ] (throw ''
  config-parser-1.0.0 normalize: job must be either:
  - true        (the name of the job is the one of the attribute,
                 this is the default behaviour)
  - false       (the package is excluded from CI, always)
  - "_excluded" (the package is excluded from CI, always)
  - "_deps"     (the package is considered by the CI as a dependency)
  - "_allJobs"  (the job is triggered only when testing all existing jobs)
  - "_all"      (the job is triggered only when testing all coqPackages)
  - a string which corresponds both to the job name
    and an attribute in coqPackages.
 ''); };
  normalize-pkg = name: pkg:
    if name != "rocqPackages" && name != "coqPackages" then pkg else
      mapAttrs normalize-coqpkg pkg;
  normalize-bundle = _name: b:
    mapAttrs normalize-pkg b
    // optionalAttrs (b ? rocqPackages && ! b ? coqPackages) { isRocq = true; };
in rec {
  format = "1.0.0";
  attribute = config.attribute or "template";
  shell-attribute = config.shell-attribute or attribute;
  nixpkgs = config.nixpkgs or initial.nixpkgs;
  pname = config.pname or attribute;
  shell-pname = config.shell-pname or pname;
  coqproject = config.coqproject or "_CoqProject";
  default-bundle = config.default-bundle or "default";
  cachix = config.cachix or { coq = {}; };
  bundles = mapAttrs normalize-bundle
    (config.bundles or { default = {}; });
  buildInputs = config.buildInputs or [];
  src = config.src or
    (if pathExists (/. + initial.src)
        -> pathExists (/. + initial.src + "/.git")
     then fetchGit (
       if false # replace by a version check when supported
                # cf https://github.com/NixOS/nix/issues/1837
       then { url = initial.src; shallow = true; } else initial.src)
     else /. + initial.src);
}
