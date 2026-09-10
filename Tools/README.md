# Notary Tools

This directory contains public build, deployment, and maintenance helpers.

- `deploy.sh` bootstraps Notary on managed Macs, persists Jamf reporting flags,
  ensures the required Jamf Extension Attributes exist, and installs the
  LaunchDaemon.
- `gen_version.sh` updates generated version metadata.

Confidential build inputs such as the real Ministry transport implementation are
intentionally not part of the public source tree. Authorized Ministry builds keep
those files below `*.local/` directories.
