# Coq Nix Toolbox

Nix helper scripts to automate local builds and CI

## How to use

### Standalone

Installing Nix locally is a prerequisite for this installation method (but a good thing to do anyway to take the most advantage of this toolbox). See https://nixos.org/download.html.
Additionally, in order to use binary caches from recognized organizations, please do
```bash
nix-env -iA nixpkgs.cachix && cachix use coq && cachix use coq-community && cachix use math-comp
```
This only needs to be performed once, after the installation of Nix.

Then, run the following commands at the root of your project (using a project-specific name instead of YOURPACKAGENAME, below) :

```bash
nix-shell https://coq.inria.fr/nix/toolbox --arg do-nothing true --run generateNixDefault
nix-shell --arg do-nothing true --run "initNixConfig YOURPACKAGENAME"
```

This will create an initial `.nix/config.nix` that you should now manually edit.
This file contains comments explaining each available option.

Once you have finished editing `.nix/config.nix`, you may generate GitHub Actions workflow(s) by running:

```bash
nix-shell --arg do-nothing true --run "genNixActions"
```

Do not forget to commit the new files.

## Overlays

You can create directories named after a Coq package and containing `default.nix` files in `.nix/coq-overlays` to override the contents of `coqPackages`.
This can be useful in the following case:

- You depend on a package or a version of a package that is not yet available in nixpkgs.
- The package that you are building is available in nixpkgs but its dependencies have changed.
- The package that you are building is not yet available in nixpkgs.


To amend a package already present in nixpkgs, just run `nix-shell --run "fetchCoqOverlay PACKAGENAME"`.
To create a package from scratch, run `nix-shell --run "createOverlay PACKAGENAME"` and refer to the nixpkgs documentation available at https://nixos.org/manual/nixpkgs/unstable/#sec-language-coq.

## Bundles and jobs

Bundles are defined in your `config.nix` file. If you didn't change this part of the auto-generated file, you have a single bundle called "default".
Bundles are used to create sets of compatible packages. You can override the version of some packages and you can explicitly exclude some incompatible packages.

Jobs represent buildable outputs. You can build any package in `coqPackages` (including any package defined in your `.nix/coq-overlays` directory) with the following command:

```
nix-build --argstr job PACKAGENAME
```
One can replace `PACKAGENAME` with:
- `_allJobs` to compile all Coq packages that are explicitly mentioned in the `config.nix` file and not explicitly excluded
- `_all` to compile all Coq packages that are not explicitly excluded

If the package depends on your main package, then it will use its local version as a dependency.

You can also specify the bundle to use like this:
```
nix-build --argstr bundle BUNDLENAME --argstr job PACKAGENAME
```

In case the `bundle` argument is omitted, the default bundle defined in `config.nix` is used.

If, for instance, you need to fix a reverse dependency of your project because it fails in CI, you can use the following command to get the dependencies for this reverse dependency:

```
nix-shell --argstr bundle BUNDLENAME --argstr job PACKAGENAME
```

This command will build all the dependencies of `PACKAGENAME`, including your project from the current sources. If these correspond to a version that has been tested in CI and you have activated Cachix (both so that CI pushes to it and on your local machine to use it), then this step should only fetch pre-built dependencies.

Again, the `bundle` argument is optional.

## Available shell hooks

When you run `nix-shell`, you get an environment with a few available commands:

- `nixHelp`: lists the available commands.
- `ppNixEnv`: displays the list of available packages and their versions.
- `generateNixDefault`: regenerates the `default.nix` file from the template in *this* repository ([`project-default.nix`](project-default.nix)).
   This command should only be used in the **Standalone** installation method.
- `ppBundle`: print debug information for the current bundle. A bundle is a set of compatible versions of packages, as described in `.nix/config.nix` (or `.nix/fallback-config.nix` if the latter does not exist).
- `ppBundles`: print the name of all available bundles, each can be passed to `nix-shell` to get different packages in your shell.
- `ppBundleSet`: print a detailed account of what each bundle contains.
- `initNixConfig`: create an initial `.nix/config.nix` file.
- `nixEnv`: displays the list of Nix store locations for all the available packages.
- `fetchCoqOverlay`: fetch a derivation file from nixpkgs that you may then edit locally to override a package.
- `createOverlay`: create a fresh derivation file from a template, which could then be added to nixpkgs.
- `cachedMake`: compile the project by reusing build outputs cached (generally thanks to Cachix).
- `genNixActions`: generates GitHub one actions file per bundle, for testing dependencies and reverse dependencies.

These three commands update the nixpkgs version to use (will create or override `.nix/nixpkgs.nix`):
- `updateNixpkgsUnstable`: update to the latest nixpkgs-unstable.
- `updateNixpkgsMaster`: update to the head of `master` of nixpkgs.
- `updateNixpkgs`: update to the specified owner and ref.

After one of these three commands, you should leave and re-enter `nix-shell` if you want the update to be taken into account (e.g., before calling `genNixActions`).

## Arguments accepted by `nix-shell`

One can pass the following arguments to `nix-shell` or `nix-build`:
- `--arg do-nothing true`: do not even provide Coq, just enough context to execute the above commands.
- `--argstr bundle t`: select the bundle `t` (one can use the above commands `ppBundles` to know the options and `ppBundleSet` to see their contents)
- `--arg override '{p1 = v1; ...; pn = vn;}'`: a very condensed inline way to select specific versions of `coq` or any package from `coqPackages` or `ocamlPackages`. E.g. `--arg override '{coq = "8.12"; ...; mathcomp = "1.12.0";}'` to override the current default bundle with the given versions.
- `--arg withEmacs true`: provide a ready to use version of emacs with proofgeneral; for the sake of reproducibility this will **not** use your system emacs nor will it use your user configuration.
- `--argstr job p`: provide the dependencies for (in case of `nix-shell`) or build (in case of `nix-build`) Coq package `p` instead of the current project, but using the current version of the current project. Combined with `--argstr bundle t` this gives a fully configurable way to test reverse dependencies for various configurations.

## Testing `coqPackages` updates in nixpkgs

To test a PR on nixpkgs that modifies the `coqPackages` set, clone this repository, `cd` into it, and run:

```
nix-shell --arg do-nothing true --run "updateNixpkgs <pr_owner> <pr_branch>"
nix-shell --arg do-nothing true --run "genNixActions"
```

Then, open a draft PR with the generated changes here.

Once the PR on nixpkgs has been merged, you can transform the draft PR into one that updates the version in use in coq-nix-toolbox by running the following commands, adapting the commit message and marking the PR as ready to merge:

```
nix-shell --arg do-nothing true --run "updateNixpkgsMaster"
nix-shell --arg do-nothing true --run "genNixActions"
```
