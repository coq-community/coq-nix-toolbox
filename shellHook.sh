#! /usr/bin/bash

printNixEnv () {
  echo "Here is your work environement"
  echo "nativeBuildInputs:"
  for x in $nativeBuildInputs; do printf "  "; echo $x | cut -d "-" -f "2-"; done
  echo "buildInputs:"
  for x in $buildInputs; do printf "  "; echo $x | cut -d "-" -f "2-"; done
  echo "propagatedBuildInputs:"
  for x in $propagatedBuildInputs; do printf "  "; echo $x | cut -d "-" -f "2-"; done
  echo "you can pass option --arg override '{coq = \"x.y\"; ...}' to nix-shell to change packages versions"
}
nixEnv () {
  for x in $buildInputs; do echo $x; done
  for x in $propagatedBuildInputs; do echo $x; done
}

generateNixDefault () {
  cat $currentDir/project-default.nix > default.nix
  HASH=$(git ls-remote https://github.com/coq-community/coq-nix-toolbox refs/heads/master | cut -f1)
  sed -i "s/<coq-nix-toolbox-sha256>/$HASH/" default.nix
}

updateNixpkgsUnstable (){
  HASH=$(git ls-remote https://github.com/NixOS/nixpkgs refs/heads/nixpkgs-unstable | cut -f1);
  URL=https://github.com/NixOS/nixpkgs/archive/$HASH.tar.gz
  SHA256=$(nix-prefetch-url --unpack $URL)
  mkdir -p $configSubDir
  echo "fetchTarball {
    url = $URL;
    sha256 = \"$SHA256\";
  }" > $configSubDir/nixpkgs.nix
}

updateNixpkgsMaster (){
  HASH=$(git ls-remote https://github.com/NixOS/nixpkgs refs/heads/master | cut -f1)
  URL=https://github.com/NixOS/nixpkgs/archive/$HASH.tar.gz
  SHA256=$(nix-prefetch-url --unpack $URL)
  mkdir -p $configSubDir
  echo "fetchTarball {
    url = $URL;
    sha256 = \"$SHA256\";
  }" > $configSubDir/nixpkgs.nix
}

updateNixpkgs (){
  if [[ -n "$1" ]]
  then if [[ -n "$2" ]]; then B=$2; else B="master"; fi
       HASH=$(git ls-remote https://github.com/$1/nixpkgs refs/heads/$B | cut -f1)
       URL=https://github.com/$1/nixpkgs/archive/$HASH.tar.gz
       SHA256=$(nix-prefetch-url --unpack $URL)
       mkdir -p $configSubDir
       echo "fetchTarball {
         url = $URL;
         sha256 = \"$SHA256\";
       }" > $configSubDir/nixpkgs.nix
  else
      echo "error: usage: updateNixpkgs <github username> [branch]"
      echo "otherwise use updateNixpkgsUnstable or updateNixpkgsMaster"
  fi
}

nixInput (){
    echo $jsonInput
}

nixInputs (){
    echo $jasonInputs
}

initNixConfig (){
  F=$currentDir/$configSubDir/config.nix;
  if [[ -f $F ]]
    then echo "$F already exists"
    else if [[ -n "$1" ]]
      then echo "{" > $F
           echo "  coq-attribute = \"$1\";" >> $F
           echo "  overrides = {};" >> $F
           echo "}" >> $F
           chmod u+w $F
      else echo "usage: initNixConfig pname"
    fi
  fi
}

fetchCoqOverlay (){
  F=$nixpkgs/pkgs/development/coq-modules/$1/default.nix
  D=$currentDir/$configSubDir/coq-overlays/$1/
  if [[ -f "$F" ]]
    then mkdir -p $D; cp $F $D; chmod u+w ${D}default.nix;
         git add ${D}default.nix
         echo "You may now amend ${D}default.nix"
    else echo "usage: fetchCoqOverlay pname"
  fi
}

cachedMake (){
  vopath="$(env -i nix-build)/lib/coq/$coq_version/user-contrib/$logpath"
  dest="$(git rev-parse --show-toplevel)/$realpath"
  echo "Compiling/Fetching and copying vo from $vopath to $realpath"
  rsync -r --ignore-existing --include=*/ $vopath/* $dest
}

nixHelp (){
  cat <<END
Available commands:
  printNixEnv
  nixEnv
  generateNixDefault
  updateNixpkgs
  updateNixpkgsUnstable
  updateNixpkgsMaster
  nixInput
  nixInputs
  initNixConfig name
  fetchCoqOverlay
  cachedMake
END
}
