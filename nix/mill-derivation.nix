{ lib, stdenv, mill, git, gnused, zstd, strip-nondeterminism, file, findutils, strace }:

{ name ? "${args'.pname}-${args'.version}", src, nativeBuildInputs ? [ ]
, passthru ? { }, patches ? [ ]

  # A function to override the dependencies derivation
, overrideDepsAttrs ? (_oldAttrs: { })

# depsSha256 is the sha256 of the dependencies
, depsSha256

# whether to put the version in the dependencies' derivation too or not.
# every time the version is changed, the dependencies will be re-downloaded
, versionInDepsName ? false

  # command to run to let mill fetch all the required dependencies for the build.
, depsWarmupTarget ? "__.compile"

, millTarget ? "__.assembly"

, ... }@args':

with builtins;
with lib;

let
  args =
    removeAttrs args' [ "overrideDepsAttrs" "depsSha256" ];

  deps = let
    depsAttrs = {
      name = "${if versionInDepsName then name else args'.pname}-deps";
      inherit src patches;

      nativeBuildInputs = [ mill git gnused zstd strip-nondeterminism file findutils ]
        ++ nativeBuildInputs;

      outputHash = depsSha256;
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";

      impureEnvVars = lib.fetchers.proxyImpureEnvVars
        ++ [ "GIT_PROXY_COMMAND" "SOCKS_SERVER" ];

      postBuild = args.postBuild or ''
        runHook preBuild

        # clean up any lingering build artifacts
        rm -rf out .nix

        mkdir -pv .nix

        echo running \"mill --home $XDG_CACHE_HOME ${
          depsWarmupTarget
        }\" to warm up the caches

        export HOME=$PWD/.nix
        export COURSIER_CACHE=$PWD/.nix
        export XDG_CACHE_HOME=$PWD/.nix
        mill --home .nix -D coursier.home=.nix/coursier -D ivy.home=.nix/.ivy2  -D user.home=.nix ${depsWarmupTarget}
        # .nix/local
      '';

      installPhase =''
        # each mill build will leave behind a worker directory
        # which will include a `io` socket, which will make the build fail
        rm -rf out/mill-worker*

        mkdir -pv $out/.nix $out/out
        ls -a .nix
        cp -r .nix/* $out/.nix
        cp -r out/* $out/out/
      '';

      postFixup = ''
        ivy_cache=$(find $out/.nix -name ivycache.json)

        echo "Removing hashes from $ivy_cache"

        # the cache will have paths that look like /build/j3c9f4mdqxiy4fsdmg7a0z3f0jb8znjz-source/.nix/
        # we need to remove the hashes which get incorrectly resolved
        # sed "$ivy_cache" -i -e "s|build/[^/]*/\.nix|build/\.nix|g"

        find $out/.nix -name 'org.scala-sbt-compiler-bridge_*' -type f -print0 | xargs -r0 strip-nondeterminism

        # set impure "inputsHash": <num> to just one
        find $out/out -name 'meta.json' -type f -print0 | xargs -r0 sed -re 's/(-?[0-9]+)/1/g'

        find $out/.nix -type d -empty -delete
        find $out/out -type d -empty -delete
      '';
    };
  in stdenv.mkDerivation (depsAttrs // overrideDepsAttrs depsAttrs);
in stdenv.mkDerivation (args // {
  nativeBuildInputs = [ mill zstd ] ++ nativeBuildInputs;

  postConfigure = (args.postConfigure or "") + ''
    rm -rf out .nix

    echo extracting dependencies
    mkdir .nix
    cp -r ${deps}/out out
    cp -r ${deps}/.nix $NIX_BUILD_TOP/.nix
    chmod -R +rwX $NIX_BUILD_TOP/.nix out
    echo hellothere
  '';

  buildPhase = ''
    export HOME=$PWD/.nix
    export COURSIER_CACHE=$NIX_BUILD_TOP/.nix
    mill --home $NIX_BUILD_TOP/.nix -D coursier.home=$NIX_BUILD_TOP/.nix/coursier -D ivy.home=$NIX_BUILD_TOP/.nix/.ivy2 -D user.home=$NIX_BUILD_TOP/.nix ${depsWarmupTarget}
    # ${strace}/bin/strace -f mill --home .nix -D coursier.home=.nix/coursier -D ivy.home=.nix/.ivy2 -D user.home=$NIX_BUILD_TOP/.nix ${depsWarmupTarget}

    #mill --home .nix -D user.home=$NIX_BUILD_TOP/.nix ${millTarget}
  '';

  installPhase = ''
    touch $out
    '';

  passthru = { inherit deps; };
})
