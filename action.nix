{ lib }:
with builtins; with lib; let
  stepCommitToInitiallyCheckout = {
    name = "Determine which commit to initially checkout";
    run = ''
      if [ ''${{ github.event_name }} = "push" ]; then
        echo "target_commit=''${{ github.sha }}" >> $GITHUB_ENV
      else
        echo "target_commit=''${{ github.event.pull_request.head.sha }}" >> $GITHUB_ENV
      fi
    '';
  };
  stepCheckout1 = {
    name =  "Git checkout";
    uses =  "actions/checkout@v4";
    "with" = {
      fetch-depth = 0;
      ref = "\${{ env.target_commit }}";
    };
  };
  stepCommitToTest = {
    name = "Determine which commit to test";
    run = ''
      if [ ''${{ github.event_name }} = "push" ]; then
        echo "tested_commit=''${{ github.sha }}" >> $GITHUB_ENV
      else
        merge_commit=$(git ls-remote ''${{ github.event.repository.html_url }} refs/pull/''${{ github.event.number }}/merge | cut -f1)
        mergeable=$(git merge --no-commit --no-ff ''${{ github.event.pull_request.base.sha }} > /dev/null 2>&1; echo $?; git merge --abort > /dev/null 2>&1 || true)
        if [ -z "$merge_commit" -o "x$mergeable" != "x0" ]; then
          echo "tested_commit=''${{ github.event.pull_request.head.sha }}" >> $GITHUB_ENV
        else
          echo "tested_commit=$merge_commit" >> $GITHUB_ENV
        fi
      fi
    '';
  };
  stepCheckout2 = {
    name =  "Git checkout";
    uses =  "actions/checkout@v4";
    "with" = {
      fetch-depth = 0;
      ref = "\${{ env.tested_commit }}";
    };
  };
  stepCachixInstall = {
    name =  "Cachix install";
    uses =  "cachix/install-nix-action@v30";
    "with".nix_path = "nixpkgs=channel:nixpkgs-unstable";
  };
  stepCachixUse = { name, authToken ? null,
                    signingKey ? null, extraPullNames ? null }: {
    name =  "Cachix setup ${name}";
    uses =  "cachix/cachix-action@v15";
    "with" = { inherit name; } //
             (optionalAttrs (!isNull authToken) {
               authToken = "\${{ secrets.${authToken} }}";
             }) // (optionalAttrs (!isNull signingKey) {
               signingKey = "\${{ secrets.${signingKey} }}";
             }) // (optionalAttrs (!isNull extraPullNames) {
               extraPullNames = concatStringsSep ", " extraPullNames;
             });
  };
  stepCachixUseAll = cachixAttrs: let
    cachixList = attrValues
      (mapAttrs (name: v: {inherit name;} // v) cachixAttrs); in
    if cachixList == [] then [] else  let
      writableAuth = filter (v: v?authToken) cachixList;
      writableToken = filter (v: v?signingKey) cachixList;
      readonly = filter (v: !v?authToken && !v?signingKey) cachixList;
      reordered = writableAuth ++ writableToken ++ readonly;
    in
      if length writableToken + length writableAuth > 1 then
        throw ("Cannot have more than one authToken " +
              "or signingKey over all cachix")
      else [ (stepCachixUse (head reordered // {
        extraPullNames = map (v: v.name) (tail reordered);
      })) ];

  stepGetDerivation = { job, bundles ? [] }:
    let bundlestr = if isList bundles then "\${{ matrix.bundle }}" else bundles; in {
    name = "Getting derivation for current job (${job})";
    id = "stepGetDerivation";
    run = ''
      NIXPKGS_ALLOW_UNFREE=1 nix-build --no-out-link \
         --argstr bundle "${bundlestr}" --argstr job "${job}" \
         --dry-run 2> err > out || (touch fail; true)
    '';
  };

  stepErrorReporting = {
    name = "Error reporting";
    run = ''
        echo "out="; cat out
        echo "err="; cat err
    '';
  };

  stepFailureCheck = {
    name = "Failure check";
    run = "if [ -e fail ]; then exit 1; else exit 0; fi;";
  };

  stepCheck = {
    name = "Checking presence of CI target for current job";
    id = "stepCheck";
    run = "(echo -n status=; cat out | grep \"built:\" | sed \"s/.*/built/\") >> $GITHUB_OUTPUT";
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
      steps = [ stepCommitToInitiallyCheckout stepCheckout1
                stepCommitToTest stepCheckout2 stepCachixInstall ]
              ++ (stepCachixUseAll cachix)
              ++ [ (stepGetDerivation { inherit job bundles; }) 
                    stepErrorReporting stepFailureCheck stepCheck ]
              ++ (map (job: stepBuild { inherit job bundles; }) jdeps)
              ++ [ (stepBuild { inherit job bundles; current = true; }) ];
    } // (optionalAttrs (isList bundles) {strategy.matrix.bundle = bundles;});
  };

  mkJobs = { jobs ? [], bundles ? [], deps ? {}, cachix ? {}, suffix ? false }@args:
    foldl (action: job: action // (mkJob ({ inherit job; } // args))) {} jobs;

  mkActionFromJobs = { actionJobs, bundles ? [], push-branches ? [] }:
    let
      workflow_path = ".github/workflows/nix-action-${toString bundles}.yml";
    in {
      name = "Nix CI for bundle ${toString bundles}";
      on = {
        push.branches = push-branches;
        pull_request.paths = [ workflow_path ];
        pull_request_target = {
          types = [ "opened" "synchronize" "reopened" ];
          paths-ignore = [ workflow_path ];
        };
      };
      jobs = actionJobs;
    };

  mkAction = { jobs ? [], bundles ? [], deps ? {}, cachix ? {} }@args:
      { push-branches ? [] }:
    mkActionFromJobs {inherit bundles push-branches; actionJobs = mkJobs args; };

in { inherit mkJob mkJobs mkAction; }
