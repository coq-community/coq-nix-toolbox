# This file was generated from `meta.yml`, please do not edit manually.
# Follow the instructions on https://github.com/coq-community/templates to regenerate.
# this config parser reads a config file with its format attributes
# (or default to the last available format)
prefix:
with builtins;
let
  optionalImport = f: d:
    if (isPath f || isString f) && pathExists f then import f else d;
  get-path = f: let local = prefix + "/.nix/${f}"; in
    if pathExists local then local else ./. + "/${f}";
in
{
  config-file ? get-path "config.nix",
  fallback-file ? get-path "fallback-config.nix",
  nixpkgs-file ? get-path "nixpkgs.nix",
  shellHook-file ? get-path "shellHook.sh",
  overlays-dir ? get-path "overlays",
  coq-overlays-dir ? get-path "coq-overlays",
  ocaml-overlays-dir ? get-path "ocaml-overlays",
  config ? {},
  withEmacs ? false,
  print-env ? false,
  do-nothing ? false,
  update-nixpkgs ? false,
  ci ? false,
  ci-step ? null,
  inNixShell ? null
}@args:
let
  do-nothing = (args.do-nothing or false) || update-nixpkgs;
  input = {
    config = optionalImport config-file (optionalImport fallback-file {})
      // config;
    nixpkgs = optionalImport nixpkgs-file (throw "cannot find nixpkgs");
  };
in
let tmp-pkgs = import input.nixpkgs {}; in
with (tmp-pkgs.coqPackages.lib or tmp-pkgs.lib);
if (input.config.format or "1.0.0") == "1.0.0" then
  let
    inNixShell = args.inNixShell or trivial.inNixShell;
    attribute-from = coq-attribute: "coqPackages.${coq-attribute}";
    logpath-from = namespace: concatStringsSep "/" (splitString "." namespace);
    config = rec {
      format = "1.0.0";
      coq-attribute = input.config.coq-attribute or "template";
      attribute = input.config.attribute or (attribute-from coq-attribute);
      nixpkgs = input.config.nixpkgs or input.nixpkgs;
      ppath = input.config.ppath or (splitString "." attribute);
      pname = input.config.pname or (last ppath);
      namespace = input.config.namespace or ".";
      logpath = input.config.logpath or (logpath-from namespace);
      realpath = input.config.realpath or ".";
      select = input.config.select or "default";
      inputs = input.config.inputs or { default = {}; };
      override = input.config.override or {};
      src = input.config.src or fetchGit (
        if false # replace by a version check when supported
                 # cf https://github.com/NixOS/nix/issues/1837
        then { url = prefix; shallow = true; } else prefix); };
  in
  with config; switch-if [
    { cond = attribute-from coq-attribute != attribute;
      out = throw "One cannot set both `coq-attribute` and `attribute`."; }
    { cond = logpath-from namespace != config.logpath;
      out = throw "One cannot set both `namespace` and `logpath`."; }
  ] (let
    mk-overlays = path: callPackage:
      if !pathExists path then {}
      else mapAttrs (x: _v: callPackage (path + "/${x}") {}) (readDir path);
      # preparing inputs
    inputs = mapAttrs
      (_: i: foldl recursiveUpdate {} [
        (setAttrByPath ppath { override.version = "${src}"; ci = true; })
        i config.override
      ]) config.inputs;
    do-override = pkg: cfg:
      let pkg' = if cfg?override
          then pkg.override or (x: pkg) cfg.override else pkg; in
        if cfg?overrideAttrs
        then pkg'.overrideAttrs cfg.overrideAttrs else pkg';
    mk-instance = input: let
      nixpkgs-overrides =
        self: super: mapAttrs (n: ov: do-override super.${n} ov)
          (removeAttrs input [ "coqPackages" "ocamlPackages" ]);
      ocaml-overrides =
        self: super: mapAttrs (n: ov: do-override super.${n} ov)
          (input.ocamlPackages or {});
      coq-overrides =
        self: super: mapAttrs
          (n: ov: do-override (super.${n} or
            (makeOverridable self.mkCoqDerivation {
              pname = "${n}"; version = "${src}";
            })) ov)
          (input.coqPackages or {});
      fold-override = foldl (fpkg: override: fpkg.overrideScope' override);
      overlays = [
        (self: super: mk-overlays overlays-dir self.callPackage)
        nixpkgs-overrides
        (self: super: { coqPackages = fold-override super.coqPackages ([
          (self: super: mk-overlays coq-overlays-dir self.callPackage)
          coq-overrides
          (self: super: { coq = super.coq.override {
            customOCamlPackages = fold-override super.coq.ocamlPackages [
              (self: super: mk-overlays ocaml-overlays-dir self.callPackage)
              ocaml-overrides
            ];};})
        ]);})
        (self: super: { coqPackages =
          super.coqPackages.filterPackages
            (! (super.coqPackages.coq.dontFilter or false)); })
      ];
      pkgs = import config.nixpkgs { inherit overlays; };
      ci-coqpkgs = step: attrValues (filterAttrs (n: v:
          let k = input.coqPackages.${n}.ci or false; in
          switch-if [
            { cond = k == true; out = isNull step || step == 2; }
            { cond = isInt k;   out = isNull step || step == k; }
          ] false) pkgs.coqPackages);
    in rec {
        inherit input pkgs;
        default-coq-derivation =
          makeOverridable pkgs.coqPackages.mkCoqDerivation
            { inherit pname; version = "${src}"; };
        this-pkg = attrByPath ppath default-coq-derivation pkgs;
        emacs = with pkgs; emacsWithPackages
          (epkgs: with epkgs.melpaStablePackages; [ proof-general ]);
        ci-pkgs = step: switch-if [
          { cond = step == 0;
            out = (this-pkg.buildInputs or []) ++
                  (this-pkg.propagatedBuildInputs or []) ++
                  ci-coqpkgs step; }
          { cond = step == 1; out = [ this-pkg ] ++ ci-coqpkgs step; }
        ] (ci-coqpkgs step);
        json_input = toJSON input;
      };
    instances = mapAttrs (_: mk-instance) inputs;
    selected-instance = instances."${select}";
    shellHook = readFile shellHook-file
        + optionalString print-env "nixEnv"
        + optionalString update-nixpkgs "updateNixPkgs; exit";
    nix-shell = with selected-instance; this-pkg.overrideAttrs (old: {
      inherit json_input shellHook;
      currentdir = prefix;
      coq_version = pkgs.coqPackages.coq.coq-version;
      inherit nixpkgs logpath realpath;

      buildInputs = optionals (!do-nothing)
        (old.buildInputs or [] ++ optional withEmacs pkgs.emacs);

      propagatedBuildInputs = optionals (!do-nothing)
        (old.propagatedBuildInputs or []);
    });
    nix-ci = step: flatten (mapAttrsToList (_: i: i.ci-pkgs step) instances);
    nix-ci-for = name: step: instances.${name}.ci-pkgs step;
    nix-default = selected-instance.this-pkg;
    nix-auto = switch-if [
      { cond = inNixShell;  out = nix-shell; }
      { cond = ci == true;  out = nix-ci ci-step; }
      { cond = isString ci; out = nix-ci-for ci ci-step; }
    ] nix-default;
    in {inherit nixpkgs config selected-instance instances shellHook
                nix-shell nix-default nix-ci nix-ci-for nix-auto; }
  )
else throw "Current config.format (${input.config.format}) not implemented"
