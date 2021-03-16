{ lib, pkgs, this-shell-pkg, task }:
with builtins; with lib;
  let
    dependencies = (this-shell-pkg.nativeBuildInputs or []) ++
                   (this-shell-pkg.buildInputs or []) ++
                   (this-shell-pkg.propagatedBuildInputs or []);
    collect-job = v: if v?job && v.job != "-" then [ v.job ] else [];
    collect-jobs = p: flatten (map collect-job (attrValues p));
    jobs = collect-jobs (task.coqPackages or {});
    keep_ = tgt: job: (job != "_excluded") &&
      (tgt == "_all" || tgt == job || (tgt == "_allJobs" && job != "_all"));
    subpkgs = job:
      let keep = n: v: keep_ job (task.coqPackages.${n}.job or "_all"); in
      attrValues (filterAttrs keep pkgs.coqPackages)
      ++ optionals (job == "_deps") dependencies;
in
{
  inherit jobs subpkgs;
  set = listToAttrs (map (job: {name = job; value = subpkgs job; }) jobs);
}
