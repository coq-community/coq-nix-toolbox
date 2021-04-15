{ lib }:
with builtins; with lib; let
  stepCheckout = {
    name =  "Git checkout";
    uses =  "actions/checkout@v2";
    "with".fetch-depth =  0;
  };
  stepCachixInstall = {
    name =  "Cachix install";
    uses =  "cachix/install-nix-action@v12";
    "with".nix_path = "nixpkgs=channel:nixpkgs-unstable";
  };
  stepCachixUse = { name, authToken ? null, signingKey ? null }: {
    name =  "Cachix setup ${name}";
    uses =  "cachix/cachix-action@v8";
    "with" = { inherit name; }
       // (optionalAttrs (!isNull authToken) {
          authToken = "\${{ secrets.${authToken} }}";
       })
       // (optionalAttrs (!isNull signingKey) {
          authToken = "\${{ secrets.${signingKey} }}";
       });
  };
  stepCachixUseAll = cachix: attrValues
    (mapAttrs (name: v: stepCachixUse ({inherit name;} // v)) cachix);

  stepBuild = {job, bundles ? [], current ? false}:
    let bundlestr = if isList bundles then "\${{ matrix.bundle }}" else bundles; in {
    name = if current then "Building/fetching current CI target"
           else "Building/fetching previous CI target: ${job}";
    run = "nix-build --no-out-link --argstr bundle \"${bundlestr}\" --argstr job \"${job}\"";
  };

  mkJob = { job, jobs ? [], bundles ? [], deps ? {}, cachix ? {}, suffix ? false }:
    let
      suffixStr = optionalString (suffix && isString bundles) "-${bundles}";
      jdeps = deps.${job} or [];
    in {
    "${job}${suffixStr}" = rec {
      runs-on = "ubuntu-latest";
      needs = map (j: "${j}${suffixStr}") (filter (j: elem j jobs) jdeps);
      steps = [ stepCheckout stepCachixInstall ] ++ (stepCachixUseAll cachix)
              ++ (map (job: stepBuild { inherit job bundles; }) jdeps)
              ++ [ (stepBuild { inherit job bundles; current = true; }) ];
    } // (optionalAttrs (isList bundles) {strategy.matrix.bundle = bundles;});
  };

  mkJobs = { jobs ? [], bundles ? [], deps ? {}, cachix ? {}, suffix ? false }@args:
    foldl (action: job: action // (mkJob ({ inherit job; } // args))) {} jobs;

  mkActionFromJobs = { actionJobs, bundles ? [] }: {
    name = "Nix CI for bundle ${toString bundles}";
    on.push.branches = [ "master" ];
    on.pull_request.branches = [ "**" ];
    jobs = actionJobs;
  };

  mkAction = { jobs ? [], bundles ? [], deps ? {}, cachix ? {} }@args:
    mkActionFromJobs {inherit bundles; actionJobs = mkJobs args; };

in { inherit mkJob mkJobs mkAction; }
