{ lib, coqPackages }:
with builtins; with lib;
let
  initialCoqPkgs = filterAttrs (_: isDerivation) coqPackages;
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
  pkgsSorted = (toposort (x: y: elem x pkgsDeps.${y}) (attrNames coqPkgs)).result;
  pkgsRevDepsSetNoAlias = foldl (done: p: foldl (done: d:
        done // { ${p} = done.${p} or {}; }
        // { ${d} = (done.${d} or {}) // { ${p} = true;} // (done.${p} or {});}
      )  done pkgsDeps.${p}
    ) {} (reverseList pkgsSorted);
  pkgsRevDepsSet = mapAttrs
     (_: p: pkgsRevDepsSetNoAlias.${pkgsRevmap.${p.name}}) initialCoqPkgs;
  pkgsRevDeps = mapAttrs (n: v: attrNames v) pkgsRevDepsSet;
in
{
  inherit pkgsDeps pkgsSorted pkgsRevDeps pkgsRevDepsSet;
}
