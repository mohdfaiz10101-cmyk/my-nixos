#!/usr/bin/env bash
# NixOS Dashboard wrapper - runs Flask app with nix-shell
exec nix-shell -p python313Packages.flask python313Packages.requests \
  --run "python3 /etc/nixos/dashboard/app.py"
