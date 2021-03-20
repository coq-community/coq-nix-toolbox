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
    name =  "Cachix setup coq";
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

  stepBuild = {job, tasks ? [], current ? false}:
    let taskstr = if isList tasks then "\${{ matrix.task }}" else tasks; in {
    name = if current then "Building/fetching current CI target"
           else "Building/fetching previous CI target: ${job}";
    run = "nix-build --no-out-link --argstr task \"${taskstr}\" --argstr job \"${job}\"";
  };

  mkJob = { job, jobs ? [], tasks ? [], deps ? {}, cachix ? {}, suffix ? false }:
    let
      suffixStr = optionalString (suffix && isString tasks) "-${tasks}";
      jdeps = deps.${job} or [];
    in {
    "${job}${suffixStr}" = rec {
      runs-on = "ubuntu-latest";
      needs = map (j: "${j}${suffixStr}") (filter (j: elem j jobs) jdeps);
      steps = [ stepCheckout stepCachixInstall ] ++ (stepCachixUseAll cachix)
              ++ (map (job: stepBuild { inherit job tasks; }) jdeps)
              ++ [ (stepBuild { inherit job tasks; current = true; }) ];
    } // (optionalAttrs (isList tasks) {strategy.matrix.task = tasks;});
  };

  mkJobs = { jobs ? [], tasks ? [], deps ? {}, cachix ? {}, suffix ? false }@args:
    foldl (action: job: action // (mkJob ({ inherit job; } // args))) {} jobs;

  mkActionFromJobs = { actionJobs, tasks ? [] }: {
    name = "Nix CI for task ${toString tasks}";
    on.push.branches = [ "master" ];
    on.pull_request.branches = [ "**" ];
    jobs = actionJobs;
  };

  mkAction = { jobs ? [], tasks ? [], deps ? {}, cachix ? {} }@args:
    mkActionFromJobs {inherit tasks; actionJobs = mkJobs args; };

in { inherit mkJob mkJobs mkAction; }