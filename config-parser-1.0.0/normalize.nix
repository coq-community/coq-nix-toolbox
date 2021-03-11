# This file is a toolbox file to parse a ./nix/config.nix
# file in format 1.0.0
{lib, config, nixpkgs, src}@initial:
with builtins; with lib;
let
  attribute-from = coq-attribute: "coqPackages.${coq-attribute}";
  logpath-from = namespace: concatStringsSep "/" (splitString "." namespace);
  config-unchecked = rec {
    format = "1.0.0";
    coq-attribute = config.coq-attribute or "template";
    shell-coq-attribute = config.shell-coq-attribute or coq-attribute;
    attribute = config.attribute or (attribute-from coq-attribute);
    shell-attribute = config.shell-attribute or (attribute-from shell-coq-attribute);
    nixpkgs = config.nixpkgs or initial.nixpkgs;
    ppath = config.ppath or (splitString "." attribute);
    shell-ppath = config.shell-ppath or (splitString "." shell-attribute);
    pname = config.pname or (last ppath);
    shell-pname = config.shell-pname or (last shell-ppath);
    coqproject = config.coqproject or "_CoqProject";
    select = config.select or "default";
    tasks = config.tasks or { default = {}; };
    buildInputs = config.buildInputs or [];
    src = config.src or
      (if pathExists (/. + (initial.src or ./.))
          -> pathExists (/. + initial.src + "/.git")
       then fetchGit (
         if false # replace by a version check when supported
                  # cf https://github.com/NixOS/nix/issues/1837
         then { url = initial.src; shallow = true; } else initial.src)
       else /. + initial.src); };
  config-checked = with config-unchecked; switch-if [
    { cond = attribute-from coq-attribute != attribute;
      out = throw "One cannot set both `coq-attribute` and `attribute`."; }
    { cond = attribute-from shell-coq-attribute != shell-attribute;
      out = throw "One cannot set both `shell-coq-attribute` and `shell-attribute`."; }
    ] config-unchecked;
in config-checked
