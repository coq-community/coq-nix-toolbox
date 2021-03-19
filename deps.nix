{ lib, coqPackages }:
with builtins; with lib;
let
  initialCoqPkgs =
    filterAttrs (_: v: isDerivation v && v != coqPackages.coq) coqPackages;
  pkgsRevmap =
     mapAttrs' (n: v: { name = "${v.name}"; value = n; }) initialCoqPkgs;
  coqPkgs = filterAttrs (n: v: elem n (attrValues pkgsRevmap)) initialCoqPkgs;
  pkgsDeps =
    let
      findInput = x: let n = pkgsRevmap."${x.name}" or null; in
                     if isNull n then [ ] else [ n ];
    in
      flip mapAttrs coqPkgs (n: v:
        flatten (map findInput (v.buildInputs ++ v.propagatedBuildInputs))
      );
  pkgsSorted = toposort (x: y: elem x pkgsDeps.${y}) (attrNames coqPkgs);
  pkgsRevDepsAttrs = foldl (done: p: foldl (done: d:
        done // { ${d} = (done.${d} or {}) // { ${p} = true;} // (done.${p} or {});}
      )  done pkgsDeps.${p}
    ) {} (reverseList pkgsSorted.result);
  pkgsRevDeps = mapAttrs (n: v: attrNames v) pkgsRevDepsAttrs;
in
{
  inherit pkgsDeps pkgsSorted pkgsRevDeps;
}
