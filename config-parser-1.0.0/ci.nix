{ lib, pkgs, this-shell-pkg, task }:
with builtins; with lib;
  let
    dependencies = (this-shell-pkg.nativeBuildInputs or []) ++
                   (this-shell-pkg.buildInputs or []) ++
                   (this-shell-pkg.propagatedBuildInputs or []);
    collect-job = v: if v?job && v.job != "_excluded" then [ v.job ] else [];
    collect-jobs = p: flatten (map collect-job (attrValues p));
    jobs = collect-jobs (task.coqPackages or {});
    excluded-job = v: if v.job == "_excluded" then [ v.job ] else [];
    excluded-jobs = p: flatten (map excluded-job (attrValues p));
    excluded = excluded-jobs (task.coqPackages or {});
    main-job = v: if v.main-job or false then [ v.job ] else [];
    main-jobs = p: flatten (map main-job (attrValues p));
    mains = main-jobs (task.coqPackages or {});
    keep_ = tgt: job: (job != "_excluded")
      && (tgt == "_all" || tgt == job
          || (tgt == "_allJobs" && elem job jobs));
    subpkgs = job:
      let keep = n: v: keep_ job (task.coqPackages.${n}.job or n); in
      attrValues (filterAttrs keep pkgs.coqPackages)
      ++ optionals (job == "_deps") dependencies;
in
{
  inherit jobs subpkgs excluded mains;
  set = listToAttrs (map (job: {name = job; value = subpkgs job; }) jobs);
}
