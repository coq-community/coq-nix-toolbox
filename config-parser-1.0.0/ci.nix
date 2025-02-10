{ lib, pkgs, this-shell-pkg, bundle }:
with builtins; with lib;
  let
    dependencies = (this-shell-pkg.nativeBuildInputs or []) ++
                   (this-shell-pkg.buildInputs or []) ++
                   (this-shell-pkg.propagatedBuildInputs or []);
    collect-job = v: if v?job && v.job != "_excluded" then [ v.job ] else [];
    collect-jobs = p: flatten (map collect-job (attrValues p));
    bundle-packages =
      if bundle ? isRocq then (bundle.rocqPackages or {})
      else  (bundle.coqPackages or {});
    jobs = collect-jobs bundle-packages;
    excluded-pkg = n: v: if v?job && v.job == "_excluded" then [ n ] else [];
    excluded = flatten (mapAttrsToList excluded-pkg bundle-packages);
    main-job = v: if (v.main-job or false) && (v.job or "" != "_excluded")
                  then [ v.job ] else [];
    main-jobs = p: flatten (map main-job (attrValues p));
    mains = main-jobs bundle-packages;
    keep_ = tgt: job: (job != "_excluded")
      && (tgt == "_all" || tgt == job
          || (tgt == "_allJobs" && elem job jobs));
    pkgs-packages =
      if bundle ? isRocq then pkgs.rocqPackages
      else pkgs.coqPackages;
    subpkgs = job:
      let keep = n: v: keep_ job (bundle.coqPackages.${n}.job or n); in
      attrValues (filterAttrs keep pkgs-packages)
      ++ optionals (job == "_deps") dependencies;
in
{
  inherit jobs subpkgs excluded mains;
  set = listToAttrs (map (job: {name = job; value = subpkgs job; }) jobs);
}
