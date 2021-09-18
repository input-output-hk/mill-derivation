{
  description = "Overlay Flake for creating mill-derivations";

  outputs = { ... }:
  let
    localOverlay = import ./overlay.nix;
  in {
    overlay = localOverlay;
    overlays = [ localOverlay ];
  };
}
