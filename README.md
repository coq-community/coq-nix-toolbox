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
nix-shell https://github.com/coq-community/coq-nix-toolbox/tarball/master --run generateNixDefault
nix-shell https://github.com/coq-community/coq-nix-toolbox/tarball/master --run "initNixConfig YOURPACKAGENAME"
```

## Available shell hooks

When you run `nix-shell`, you get an environment with a few available commands:

- `nixHelp`: lists the available commands.
- `printNixEnv`: displays the list of available packages and their versions.
- `nixEnv`: displays the list of Nix store locations for all the available packages.
- `generateNixDefault`: regenerates the `default.nix` file from the template in *this* repository ([`project-default.nix`](project-default.nix)).
- `nixTask`:
- `nixTasks`:
- `initNixConfig`: create an initial `.nix/config.nix` file.
- `fetchCoqOverlay`: fetch a derivation file from nixpkgs that you may then edit locally to override a package.
- `cachedMake`: compile the project by reusing build outputs cached thanks to Cachix.

These three commands update the nixpkgs version to use (will create or override `.nix/nixpkgs.nix`):
- `updateNixpkgsUnstable`: update to the latest nixpkgs-unstable.
- `updateNixpkgsMaster`: update to the head of `master` of nixpkgs.
- `updateNixpkgs`: update to the specified owner and ref.
