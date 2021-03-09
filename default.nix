# This file is a toolbox file to parse a .nix directory and make
# 1. a nix overlay
# 2. a shell and a build derivation
with builtins;
let
  get-path = currentDir: f: let local = currentDir + "/.nix/${f}"; in
    if pathExists local then local else ./. + "/${f}";
in
{
  currentDir ? ./., # provide he current directory
  config-file ? get-path currentDir "config.nix",
  fallback-file ? get-path currentDir "fallback-config.nix",
  nixpkgs-file ? get-path currentDir "nixpkgs.nix",
  shellHook-file ? get-path currentDir "shellHook.sh",
  overlays-dir ? get-path currentDir "overlays",
  coq-overlays-dir ? get-path currentDir "coq-overlays",
  ocaml-overlays-dir ? get-path currentDir "ocaml-overlays",
  ci-matrix ? false,
  config ? {},
  override ? {},
  ocaml-override ? {},
  global-override ? {},
  withEmacs ? false,
  print-env ? false,
  do-nothing ? false,
  update-nixpkgs ? false,
  ci-step ? null,
  ci ? (!isNull ci-step),
  inNixShell ? null
}@args:
let
  optionalImport = f: d:
    if (isPath f || isString f) && pathExists f then import f else d;
  do-nothing = (args.do-nothing or false) || update-nixpkgs || ci-matrix;
  initial = {
    config = optionalImport config-file (optionalImport fallback-file {})
      // config;
    nixpkgs = optionalImport nixpkgs-file (throw "cannot find nixpkgs");
    pkgs = import initial.nixpkgs {};
  };
in
with (initial.pkgs.coqPackages.lib or tmp-pkgs.lib);
if (initial.config.format or "1.0.0") == "1.0.0" then
  let
    inNixShell = args.inNixShell or trivial.inNixShell;
    attribute-from = coq-attribute: "coqPackages.${coq-attribute}";
    logpath-from = namespace: concatStringsSep "/" (splitString "." namespace);
    config = rec {
      format = "1.0.0";
      coq-attribute = initial.config.coq-attribute or "template";
      shell-coq-attribute = initial.config.coq-attribute or
        initial.config.shell-coq-attribute or "template";
      attribute = initial.config.attribute or (attribute-from coq-attribute);
      shell-attribute = initial.config.shell-attribute or (attribute-from shell-coq-attribute);
      nixpkgs = initial.config.nixpkgs or initial.nixpkgs;
      ppath = initial.config.ppath or (splitString "." attribute);
      shell-ppath = initial.config.shell-ppath or (splitString "." shell-attribute);
      pname = initial.config.pname or (last ppath);
      shell-pname = initial.config.shell-pname or (last shell-ppath);
      namespace = initial.config.namespace or ".";
      logpath = initial.config.logpath or (logpath-from namespace);
      realpath = initial.config.realpath or ".";
      select = initial.config.select or "default";
      inputs = initial.config.inputs or { default = {}; };
      src = initial.config.src or (fetchGit (
        if false # replace by a version check when supported
                 # cf https://github.com/NixOS/nix/issues/1837
        then { url = currentDir; shallow = true; } else currentDir)); };
  in
  with config; switch-if [
    { cond = attribute-from coq-attribute != attribute;
      out = throw "One cannot set both `coq-attribute` and `attribute`."; }
    { cond = attribute-from shell-coq-attribute != shell-attribute;
      out = throw "One cannot set both `shell-coq-attribute` and `shell-attribute`."; }
    { cond = logpath-from namespace != config.logpath;
      out = throw "One cannot set both `namespace` and `logpath`."; }
  ] (let
    mk-overlays = path: callPackage:
      if !pathExists path then {}
      else mapAttrs (x: _v: callPackage (path + "/${x}") {}) (readDir path);
      # preparing inputs
    inputs = let
        mk-inputs = pre: x:
          setAttrByPath pre (mapAttrs (n: v: {override.version = v;}) x);
      in mapAttrs
      (_: i: foldl recursiveUpdate {} [
        (setAttrByPath shell-ppath
          { override.version = "${src}"; ci = "shell"; })
        (setAttrByPath ppath { override.version = "${src}"; ci = 0; })
        i
        (mk-inputs [ "coqPackages" ] override)
        (mk-inputs [ "ocamlPackages" ] ocaml-override)
        (mk-inputs [ ] global-override)
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
      ci-coqpkgs = step: attrValues (filterAttrs (n: v:
            let step-n = to-step (input.coqPackages.${n}.ci.step or false); in
            (step-n != "NOCI") && ((step == step-n) || step == "all"))
          pkgs.coqPackages);
    in rec {
        inherit input pkgs;
        default-coq-derivation =
          makeOverridable pkgs.coqPackages.mkCoqDerivation
            { inherit pname; version = "${src}"; };
        this-pkg = attrByPath ppath default-coq-derivation pkgs;
        this-shell-pkg = attrByPath shell-ppath default-coq-derivation pkgs;
        emacs = with pkgs; emacsWithPackages
          (epkgs: with epkgs.melpaStablePackages; [ proof-general ]);
        ci-pkgs = raw-step: let step = to-step raw-step; in
          switch step [
          { case = "dependencies";
            out = (this-shell-pkg.nativeBuildInputs or []) ++
                  (this-shell-pkg.buildInputs or []) ++
                  (this-shell-pkg.propagatedBuildInputs or []) ++
                  ci-coqpkgs step; }
          ] (ci-coqpkgs step);
        jsonInput = toJSON input;
      };
    instances = mapAttrs (_: mk-instance) inputs;
    selected-instance = instances."${select}";
    shellHook = readFile shellHook-file
        + optionalString print-env "\nprintNixEnv; exit"
        + optionalString update-nixpkgs "\nupdateNixPkgs; exit"
        + optionalString ci-matrix "\nnixInputs; exit";
    jasonInputs = toJSON (attrNames inputs);
    configDir = ".nix";
    nix-shell = with selected-instance; this-shell-pkg.overrideAttrs (old: {
      inherit jsonInput jasonInputs shellHook nixpkgs logpath realpath;
      inherit configDir currentDir;
      coq_version = pkgs.coqPackages.coq.coq-version;

      nativeBuildInputs = optionals (!do-nothing)
        (old.propagatedBuildInputs or []);

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
    in
nix-shell.overrideAttrs (o: {
  configDir = ".";
  passthru = (o.passthru or {}) // { inherit nixpkgs config selected-instance instances shellHook
          nix-shell nix-default nix-ci nix-ci-for nix-auto; };
}))
else throw "Current config.format (${initial.config.format}) not implemented"
