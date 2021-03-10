# This file is a toolbox file to parse a ./nix/config.nix
# file in format 1.0.0
{lib, config, nixpkgs}@initial:
with builtins; with lib;
let
  attribute-from = coq-attribute: "coqPackages.${coq-attribute}";
  logpath-from = namespace: concatStringsSep "/" (splitString "." namespace);
  config-unchecked = rec {
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
    src = initial.config.src or
      (if pathExists (/. + initial.src or ./.) -> pathExists (/. + initial.src + "/.git")
       then fetchGit (
         if false # replace by a version check when supported
                  # cf https://github.com/NixOS/nix/issues/1837
         then { url = initial.src; shallow = true; } else initial.src)
       else /. + initial.src); };
  config = with config-unchecked; switch-if [
    { cond = attribute-from coq-attribute != attribute;
      out = throw "One cannot set both `coq-attribute` and `attribute`."; }
    { cond = attribute-from shell-coq-attribute != shell-attribute;
      out = throw "One cannot set both `shell-coq-attribute` and `shell-attribute`."; }
    { cond = logpath-from namespace != logpath;
      out = throw "One cannot set both `namespace` and `logpath`."; }
    ] config-unchecked;
in config
