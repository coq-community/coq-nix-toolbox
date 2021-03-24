#! /usr/bin/bash

export currentDir=$PWD
export configDir=$currentDir/.nix

nixCommands=()
addNixCommand (){
  nixCommands+=($1)
}

nixHelp (){
  echo "Available commands:"
  for cmd in "${nixCommands[@]}"; do echo "- $cmd" ; done
}

printNixEnv () {
  echo "Here is your work environement"
  echo "nativeBuildInputs:"
  for x in $nativeBuildInputs; do printf -- "- "; echo $x | cut -d "-" -f "2-"; done
  echo "buildInputs:"
  for x in $buildInputs; do printf -- "- "; echo $x | cut -d "-" -f "2-"; done
  echo "propagatedBuildInputs:"
  for x in $propagatedBuildInputs; do printf -- "- "; echo $x | cut -d "-" -f "2-"; done
  echo "you can pass option --arg override '{coq = \"x.y\"; ...}' to nix-shell to change packages versions"
}
addNixCommand printNixEnv

ppNixEnv () {
  echo "Available packages:"
  for x in $buildInputs
  do printf -- "- "
     pkgv=$(echo $x | cut -d "-" -f "2-")
     echo $(echo $pkgv | sed "s/coq[0-9][^\-]*-//")
  done
  for x in $propagatedBuildInputs
  do printf -- "- "
     pkgv=$(echo $x | cut -d "-" -f "2-")
     echo $(echo $pkgv | sed "s/coq[0-9][^\-]*-//")
  done
}
addNixCommand ppNixEnv

nixEnv () {
  for x in $buildInputs; do echo $x; done
  for x in $propagatedBuildInputs; do echo $x; done
}
addNixCommand nixEnv

updateNixToolBox () {
  HASH=$(git ls-remote https://github.com/coq-community/coq-nix-toolbox refs/heads/master | cut -f1)
  mkdir -p $configDir
  echo "\"$HASH\"" > $configDir/coq-nix-toolbox.nix
}
addNixCommand updateNixToolBox

generateNixDefault () {
  cat $toolboxDir/project-default.nix > $currentDir/default.nix
  updateNixToolBox
}
addNixCommand generateNixDefault

updateNixpkgsUnstable (){
  HASH=$(git ls-remote https://github.com/NixOS/nixpkgs refs/heads/nixpkgs-unstable | cut -f1);
  URL=https://github.com/NixOS/nixpkgs/archive/$HASH.tar.gz
  SHA256=$(nix-prefetch-url --unpack $URL)
  mkdir -p $configDir
  echo "fetchTarball {
    url = $URL;
    sha256 = \"$SHA256\";
  }" > $configDir/nixpkgs.nix
}
addNixCommand updateNixpkgsUnstable

updateNixpkgsMaster (){
  HASH=$(git ls-remote https://github.com/NixOS/nixpkgs refs/heads/master | cut -f1)
  URL=https://github.com/NixOS/nixpkgs/archive/$HASH.tar.gz
  SHA256=$(nix-prefetch-url --unpack $URL)
  mkdir -p $configDir
  echo "fetchTarball {
    url = $URL;
    sha256 = \"$SHA256\";
  }" > $configDir/nixpkgs.nix
}
addNixCommand updateNixpkgsMaster

updateNixpkgs (){
  if [[ -n "$1" ]]
  then if [[ -n "$2" ]]; then B=$2; else B="master"; fi
       HASH=$(git ls-remote https://github.com/$1/nixpkgs refs/heads/$B | cut -f1)
       URL=https://github.com/$1/nixpkgs/archive/$HASH.tar.gz
       SHA256=$(nix-prefetch-url --unpack $URL)
       mkdir -p $configDir
       echo "fetchTarball {
         url = $URL;
         sha256 = \"$SHA256\";
       }" > $configDir/nixpkgs.nix
  else
      echo "error: usage: updateNixpkgs <github username> [branch]"
      echo "otherwise use updateNixpkgsUnstable or updateNixpkgsMaster"
  fi
}
addNixCommand updateNixpkgs

nixTask (){
    echo $jsonTask
}
addNixCommand nixTask

ppTask (){
    echo $jsonTask | json2yaml
}
addNixCommand ppTask

nixTasks (){
    echo $jsonTasks
}
addNixCommand nixTasks

ppTasks (){
    echo $jsonTasks | json2yaml
}
addNixCommand ppTasks

ppTaskSet (){
    echo $jsonTaskSet | json2yaml
}
addNixCommand ppTaskSet

ppCIbyTask (){
    echo $jsonCIbyTask | json2yaml
}
addNixCommand ppCIbyTask

ppCIbyJob (){
    echo $jsonCIbyJob | json2yaml
}
addNixCommand ppCIbyJob

ppDeps (){
    echo $jsonPkgsDeps | json2yaml
}
addNixCommand ppDeps

ppRevDeps (){
    echo $jsonPkgsRevDeps | json2yaml
}
addNixCommand ppRevDeps

ppNixAction (){
  echo $jsonAction | json2yaml
}
addNixCommand ppNixAction

genNixActions (){
  mkdir -p $currentDir/.github/workflows/
  for t in $tasks; do
    echo "generating $currentDir/.github/workflows/nix-action-$t.yml"
    nix-shell --arg do-nothing true --argstr task $t --run "ppNixAction > $currentDir/.github/workflows/nix-action-$t.yml"
  done
}
addNixCommand genNixActions

initNixConfig (){
  Orig=$toolboxDir/template-config.nix
  F=$configDir/config.nix;
  if [[ -f $F ]]; then
     echo "$F already exists"
  else if [[ -n "$1" ]]; then
       mkdir -p $configDir
       cat $Orig > $F
       sed -i "s/template/$1/" $F
    else echo "usage: initNixConfig pname"
    fi
  fi
}
addNixCommand initNixConfig

fetchCoqOverlay (){
  F=$nixpkgs/pkgs/development/coq-modules/$1/default.nix
  D=$configDir/coq-overlays/$1/
  if [[ -f "$F" ]]
    then mkdir -p $D; cp $F $D; chmod u+w ${D}default.nix;
         git add ${D}default.nix
         echo "You may now amend ${D}default.nix"
    else echo "usage: fetchCoqOverlay pname"
  fi
}
addNixCommand fetchCoqOverlay

cachedMake (){
  cproj=$currentDir/$coqproject
  cprojDir=$(dirname $cproj)
  build=$(env -i PATH=$PATH NIX_PATH=$NIX_PATH nix-build --argstr task "$selectedTask" --no-out-link)
  grep -e "^-R.*" $cproj | while read -r line; do
    realpath=$(echo $line | cut -d" " -f2)
    namespace=$(echo $line | cut -d" " -f3)
    logpath=${namespace/.//}
    vopath="$build/lib/coq/$coq_version/user-contrib/$logpath"
    dest=$cprojDir/$realpath
    if [[ -d $vopath ]]
    then echo "Compiling/Fetching and copying vo from $vopath to $realpath"
         cp -nr --no-preserve=mode,ownership  $vopath/* $dest
    else echo "Error: cannot find compiled $logpath, check your .nix/config.nix"
    fi
  done
}
addNixCommand cachedMake

if [[ -f $emacsBin ]]
then
emacs (){
  F=$currentDir/.emacs
  if ! [[ -f "$F" ]]
  then cp -u $emacsInit $F
  fi
  $emacsBin -q --load $F $*
}
addNixCommand emacs
fi
