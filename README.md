# nix-toolbox

Nix helper scripts to automate local builds and CI

## How to use

There are two supported methods of using this toolbox.

### With the coq-community templates

Generate the Nix files using the templates available at: https://github.com/coq-community/templates

You will need to put at least `nix: true` in your `meta.yml`.
Everything else is optional and is documented in [`ref.yml`](https://github.com/coq-community/templates/blob/master/ref.yml).

### Standalone

Installing Nix locally is a prerequisite for this installation method (but a good thing to do anyway to take the most advantage of this toolbox). See https://nixos.org/download.html.

Then, just run the following at the root of your project:

```
nix-shell https://coq.inria.fr/nix/toolbox --run generateNixDefault
nix-shell --run "initNixConfig YOURPACKAGENAME"
```

This will create an initial `.nix/config.yml` that you should now manually edit.
This file contains comments explaining each available option.

## Overrides

You can create directories named after a Coq package and containing `default.nix` files in `.nix/coq-overlays` to override the contents of `coqPackages`.
This can be useful in the following case:

- You depend on a package or a version of a package that is not yet available in nixpkgs.
- The package that you are building is available in nixpkgs but its dependencies changed.
- The package that you are building is not yet available in nixpkgs.

To amend a package already present in nixpkgs, just run `nix-shell --run "fetchCoqOverlay PACKAGENAME"`.
To create a package from scratch, refer to the nixpkgs documentation available at https://nixos.org/manual/nixpkgs/unstable/#sec-language-coq.

## Tasks and jobs

## Available shell hooks

When you run `nix-shell`, you get an environment with a few available commands:

- `nixHelp`: lists the available commands.
- `ppNixEnv`: displays the list of available packages and their versions.
- `generateNixDefault`: regenerates the `default.nix` file from the template in *this* repository ([`project-default.nix`](project-default.nix)).
   This command should only be used in the **Standalone** installation method.
- `ppTask`: print debug information for the current task. A task is a set of compatible versions of packages, as described in `.nix/config.nix` (or `.nix/fallback-config.nix` if the latter does not exist).
- `ppTasks`: print the name of all available tasks, each can be passed to `nix-shell` to get different packages in your shell.
- `ppTaskSet`: print a detailed account of what each task contains.
- `initNixConfig`: create an initial `.nix/config.nix` file.
- `nixEnv`: displays the list of Nix store locations for all the available packages.
- `fetchCoqOverlay`: fetch a derivation file from nixpkgs that you may then edit locally to override a package.
- `cachedMake`: compile the project by reusing build outputs cached (generally thanks to Cachix).

These three commands update the nixpkgs version to use (will create or override `.nix/nixpkgs.nix`):
- `updateNixpkgsUnstable`: update to the latest nixpkgs-unstable.
- `updateNixpkgsMaster`: update to the head of `master` of nixpkgs.
- `updateNixpkgs`: update to the specified owner and ref.

## Arguments accepted by `nix-shell`

One can pass the following arguments to `nix-shell`:
- `--arg do-nothing true`: do not even provide Coq, just enough context to execute the above commands.
- `--argstr task t`: select the task `t` (one can use the above commands `ppTasks` to know the options and `ppTaskSet` to see their contents)
- `--arg override '{p1 = v1; ...; pn = vn;}'`: a very condensed inline way to select specific versions of `coq` or any package from `coqPackages` or `ocamlPackages`. E.g. `--arg override '{coq = "8.12"; ...; mathcomp = "1.12.0";}'` to override the current default task with the given versions.
- `--arg withEmacs true`: provide a ready to use version of emacs with proofgeneral; for the sake of reproducibility this will **not** use your system emacs nor will it use your user configuration. 

One can instead use `nix-build` to build the current project, in addition to the previous options, the following options are then available
- `--argstr job p`: build coq package `p` instead of the current project, but using the current version of the current project. Combined with `--argstr task t` this gives a fully configurable way to test reverse dependencies for various configurations.
