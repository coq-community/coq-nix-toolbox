{ lib, pkgs, this-shell-pkg, medley }:
with builtins; with lib; let
  to-job = n: switch n [
    { case = -1;        out = "dependencies";}
    { case = "job--1";  out = "dependencies";}
    { case = "deps";    out = "dependencies";}
    { case = 0;         out = "main";}
    { case = "job-0";   out = "main";}
    { case = true ;     out = "all"; }
    { case = null;      out = "all"; }
    { case = false;     out = "NOCI"; }
    { case = isInt;     out = "job-${toString n}";}
    { case = isString;  out = n;}
    ] (throw "Step is not a string or an int ${toString n}");
  dependencies = (this-shell-pkg.nativeBuildInputs or []) ++
                 (this-shell-pkg.buildInputs or []) ++
                 (this-shell-pkg.propagatedBuildInputs or []);
  subpkgs = raw-job:
      let
        job = to-job raw-job;
        keep = n: v:
          let
            ipkg-n = medley.coqPackages.${n} or {};
            job-n = switch-if [
              { cond = !(ipkg-n?ci);             out = "NOCI";}
              { cond = !((ipkg-n.ci or {})?job); out = n;}
            ] (to-job ipkg-n.ci.job); in
        (job-n != "NOCI") && (job-n != "exclude") &&
        ((job == job-n) || (job == "all")); in
      attrValues (filterAttrs keep pkgs.coqPackages)
      ++ optionals (job == "dependencies") dependencies;
  collect-job = v: if v?ci && v.ci?job then [ (to-job v.ci.job) ] else [];
  collect-jobs = p: flatten (map collect-job (attrValues p));
  jobs = collect-jobs (medley.coqPackages or {});
in
{
  inherit jobs subpkgs;
  set = listToAttrs (map (job: {name = job; value = subpkgs job; }) jobs);
}