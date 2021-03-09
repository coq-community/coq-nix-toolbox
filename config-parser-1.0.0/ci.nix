{ lib, pkgs, this-shell-pkg, input }:
with builtins; with lib; let
  to-step = n: switch n [
    { case = -1;        out = "dependencies";}
    { case = "step--1"; out = "dependencies";}
    { case = "deps";    out = "dependencies";}
    { case = 0;         out = "main";}
    { case = "step-0";  out = "main";}
    { case = true ;     out = "all"; }
    { case = null;      out = "all"; }
    { case = false;     out = "NOCI"; }
    { case = isInt;     out = "step-${toString n}";}
    { case = isString;  out = n;}
    ] (throw "Step is not a string or an int ${toString n}");
  dependencies = (this-shell-pkg.nativeBuildInputs or []) ++
                 (this-shell-pkg.buildInputs or []) ++
                 (this-shell-pkg.propagatedBuildInputs or []);
  subpkgs = raw-step:
      let
        step = to-step raw-step;
        keep = n: v:
          let
            ipkg-n = input.coqPackages.${n} or {};
            step-n = switch-if [
              { cond = !(ipkg-n?ci);              out = "NOCI";}
              { cond = !((ipkg-n.ci or {})?step); out = n;}
            ] (to-step ipkg-n.ci.step); in
        (step-n != "NOCI") && (step-n != "exclude") &&
        ((step == step-n) || (step == "all")); in
      attrValues (filterAttrs keep pkgs.coqPackages)
      ++ optionals (step == "dependencies") dependencies;
  collect-step = v: if v?ci && v.ci?step then [ (to-step v.ci.step) ] else [];
  collect-steps = p: flatten (map collect-step (attrValues p));
  steps = collect-steps (input.coqPackages or {});
in
{
  inherit steps subpkgs;
  set = listToAttrs (map (step: {name = step; value = subpkgs step; }) steps);
}