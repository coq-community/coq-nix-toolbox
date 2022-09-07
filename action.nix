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
  stepCheckout = {
    name =  "Git checkout";
    uses =  "actions/checkout@v2";
    "with" = {
      fetch-depth = 0;
      ref = "\${{ env.tested_commit }}";
    };
  };
  stepCachixInstall = {
    name =  "Cachix install";
    uses =  "cachix/install-nix-action@v16";
    "with".nix_path = "nixpkgs=channel:nixpkgs-unstable";
  };
  stepCachixUse = { name, authToken ? null,
                    signingKey ? null, extraPullNames ? null }: {
    name =  "Cachix setup ${name}";
    uses =  "cachix/cachix-action@v10";
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

  stepCheck = { job, bundles ? [] }:
    let bundlestr = if isList bundles then "\${{ matrix.bundle }}" else bundles; in {
    name = "Checking presence of CI target ${job}";
    id = "stepCheck";
    run = ''
      nb_dry_run=$(NIXPKGS_ALLOW_UNFREE=1 nix-build --no-out-link \
         --argstr bundle "${bundlestr}" --argstr job "${job}" \
         --dry-run 2>&1 > /dev/null)
      echo $nb_dry_run
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

  mkJob = { job, jobs ? [], bundles ? [], deps ? {}, cachix ? {}, ci-platform, suffix ? false }:
    let
      suffixStr = optionalString (suffix && isString bundles) "-${bundles}";
      jdeps = deps.${job} or [];
    in {
    "${job}${suffixStr}" = rec {
      runs-on = if ci-platform == null then "ubuntu-latest" else ci-platform;
      needs = map (j: "${j}${suffixStr}") (filter (j: elem j jobs) jdeps);
      steps = [ stepCommitToTest stepCheckout stepCachixInstall ]
              ++ (stepCachixUseAll cachix)
              ++ [ (stepCheck { inherit job bundles; }) ]
              ++ (map (job: stepBuild { inherit job bundles; }) jdeps)
              ++ [ (stepBuild { inherit job bundles; current = true; }) ];
    } // (optionalAttrs (isList bundles) {strategy.matrix.bundle = bundles;});
  };

  mkJobs = { jobs ? [], bundles ? [], deps ? {}, cachix ? {}, ci-platform, suffix ? false }@args:
    foldl (action: job: action // (mkJob ({ inherit job; } // args))) {} jobs;

  mkActionFromJobs = { actionJobs, bundles ? [], ci-platform }: {
    name = "Nix CI for bundle ${toString bundles}${if ci-platform == null then "" else " on platform ${ci-platform}"}";
    on = {
      push.branches = [ "master" ];
      pull_request.paths = [ ".github/workflows/**" ];
      pull_request_target.types = [ "opened" "synchronize" "reopened" ];
    };
    jobs = actionJobs;
  };

  mkAction = { jobs ? [], bundles ? [], deps ? {}, cachix ? {}, ci-platform ? null }@args:
    mkActionFromJobs {inherit bundles ci-platform; actionJobs = mkJobs args; };

in { inherit mkJob mkJobs mkAction; }
