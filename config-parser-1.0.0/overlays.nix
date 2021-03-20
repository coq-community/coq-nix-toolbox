{ overlays-dir, lib, coq-overlays-dir, ocaml-overlays-dir, task,
  attribute, pname, shell-attribute, shell-pname, src }:
with builtins; with lib;
let
  mk-overlay = path: self: super:
    if !pathExists path then {} else
    let
      hasDefault = p: (readDir p)?"default.nix";
      isOverlay = x: ty: ty == "directory" && hasDefault (path + "/${x}");
      overlays = filterAttrs isOverlay (readDir path);
    in
      mapAttrs (x: _: self.callPackage (path + "/${x}") {}) overlays;
  do-override = pkg: cfg:
    let pkg' = if cfg?override
        then pkg.override or (x: pkg) cfg.override else pkg; in
      if cfg?overrideAttrs
      then pkg'.overrideAttrs cfg.overrideAttrs else pkg';
  nixpkgs-overrides =
    self: super: mapAttrs (n: ov: do-override super.${n} ov)
      (removeAttrs task [ "coqPackages" "ocamlPackages" ]);
  ocaml-overrides =
    self: super: mapAttrs (n: ov: do-override super.${n} ov)
      (task.ocamlPackages or {});
  coq-overrides =
    self: super:
    let newCoqPkg = pname: args: makeOverridable self.mkCoqDerivation
      { inherit pname; version = "${src}"; } // args;
    in
      mapAttrs (n: ov: do-override (super.${n} or
        (switch n [
          { case = attribute;       out = newCoqPkg pname {}; }
          { case = shell-attribute; out = newCoqPkg shell-pname {}; }
        ] (newCoqPkg n ((super.${n}.mk or (_: {})) self))
      )) ov) (task.coqPackages or {});
  fold-override = foldl (fpkg: override: fpkg.overrideScope' override);
  in
[
  (mk-overlay overlays-dir)
  nixpkgs-overrides
  (self: super: { coqPackages = fold-override super.coqPackages ([
    (self: super: { mkCoqDerivation = { defaultVersion ? null, ... }@args:
      super.mkCoqDerivation (args //
       { defaultVersion = if isNull defaultVersion then "master" else defaultVersion; }); })
    (mk-overlay coq-overlays-dir)
    coq-overrides
    (self: super: { coq = super.coq.override {
      customOCamlPackages = fold-override super.coq.ocamlPackages [
        (mk-overlay ocaml-overlays-dir)
        ocaml-overrides
      ];};})
  ]);})
  (self: super: { coqPackages =
    super.coqPackages.filterPackages
      (! (super.coqPackages.coq.dontFilter or false)); })
]
