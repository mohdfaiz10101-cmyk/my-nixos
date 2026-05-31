#!/usr/bin/env bash
# Compatibility wrapper. The real implementation is health-aggregator.sh.
exec /etc/nixos/scripts/health-aggregator.sh "$@"
