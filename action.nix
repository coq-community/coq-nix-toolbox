{ lib }:
with builtins; with lib; let
  stepCommitToTest = {
    name = "Determine which commit to test";
    run = ''
      if [ ''${{ github.event_name }} = "push" ]; then
        echo "tested_commit=''${{ github.sha }}" >> $GITHUB_ENV
      else
        merge_commit=$(git ls-remote ''${{ github.event.repository.html_url }} refs/pull/''${{ github.event.number }}/merge | cut -f1)
        if [ -z "$merge_commit" ]; then
          echo "tested_commit=''${{ github.event.pull_request.head.sha }}" >> $GITHUB_ENV
        else
          echo "tested_commit=$merge_commit" >> $GITHUB_ENV
        fi
      fi
    '';
  };
  stepRefToTest = {
    name = "Determine which ref to test";
    run = ''
      if [ ''${{ github.event_name }} = "push" ]; then
        echo "tested_ref=''${{ github.ref }}" >> $GITHUB_ENV
      else
        merge_commit=$(git ls-remote ''${{ github.event.repository.html_url }} refs/pull/''${{ github.event.number }}/merge | cut -f1)
        if [ -z "$merge_commit" ]; then
          echo "tested_ref=refs/pull/''${{ github.event.number }}/head" >> $GITHUB_ENV
        else
          echo "tested_ref=refs/pull/''${{ github.event.number }}/merge" >> $GITHUB_ENV
        fi
      fi
    '';
  };
  stepCheckout = {
    name =  "Git checkout";
    uses =  "actions/checkout@v2";
    "with" = {
      fetch-depth = 0;
      ref = "\${{ env.tested_ref }}";
    };
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

  stepCheck = { job, bundles ? [] }:
    let bundlestr = if isList bundles then "\${{ matrix.bundle }}" else bundles; in {
    name = "Checking presence of CI target ${job}";
    id = "stepCheck";
    run = ''
      nb_dry_run=$(NIXPKGS_ALLOW_UNFREE=1 nix-build --no-out-link \
         --argstr bundle "${bundlestr}" --argstr job "${job}" \
         --dry-run 2>&1 > /dev/null)
      echo ::set-output name=status::$(echo $nb_dry_run | grep "built:" | sed "s/.*/built/")
    '';
  };

  stepBuild = {job, bundles ? [], current ? false}:
    let bundlestr = if isList bundles then "\${{ matrix.bundle }}" else bundles; in {
    name = if current then "Building/fetching current CI target"
           else "Building/fetching previous CI target: ${job}";
    "if" = "steps.stepCheck.outputs.status == 'built'";
    run  = "NIXPKGS_ALLOW_UNFREE=1 nix-build --no-out-link --argstr bundle \"${bundlestr}\" --argstr job \"${job}\"";
  };

  mkJob = { job, jobs ? [], bundles ? [], deps ? {}, cachix ? {}, suffix ? false }:
    let
      suffixStr = optionalString (suffix && isString bundles) "-${bundles}";
      jdeps = deps.${job} or [];
    in {
    "${job}${suffixStr}" = rec {
      runs-on = "ubuntu-latest";
      needs = map (j: "${j}${suffixStr}") (filter (j: elem j jobs) jdeps);
      steps = [ stepRefToTest stepCheckout stepCachixInstall ]
              ++ (stepCachixUseAll cachix)
              ++ [ (stepCheck { inherit job bundles; }) ]
              ++ (map (job: stepBuild { inherit job bundles; }) jdeps)
              ++ [ (stepBuild { inherit job bundles; current = true; }) ];
    } // (optionalAttrs (isList bundles) {strategy.matrix.bundle = bundles;});
  };

  mkJobs = { jobs ? [], bundles ? [], deps ? {}, cachix ? {}, suffix ? false }@args:
    foldl (action: job: action // (mkJob ({ inherit job; } // args))) {} jobs;

  mkActionFromJobs = { actionJobs, bundles ? [] }: {
    name = "Nix CI for bundle ${toString bundles}";
    on = {
      push.branches = [ "master" ];
      pull_request.paths = [ ".github/workflows/**" ];
      pull_request_target.types = [ "opened" "synchronize" "reopened" ];
    };
    jobs = actionJobs;
  };

  mkAction = { jobs ? [], bundles ? [], deps ? {}, cachix ? {} }@args:
    mkActionFromJobs {inherit bundles; actionJobs = mkJobs args; };

in { inherit mkJob mkJobs mkAction; }
