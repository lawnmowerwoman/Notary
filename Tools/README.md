# Notary Tools

This directory contains public build, deployment, and maintenance helpers.

- `deploy.sh` bootstraps Notary on managed Macs, persists Jamf reporting flags,
  ensures the required Jamf Extension Attributes exist, and installs the
  LaunchDaemon.
- `gen_version.sh` updates generated version metadata.

## Activation Code Deployment

To set the local Activation Code without changing a configuration profile:

```sh
sudo /bin/zsh Tools/deploy.sh --activation=NOTXDEVMOCS2472R
```

In Jamf, add `--activation=NOTX...` to an available script parameter. Existing
deployment options can be combined with it. The script stores `activationCode`
in the existing `/var/db/notary.plist`, retaining unrelated keys, App Tokens,
token-cache metadata and existing Jamf credentials. Without this option, the
existing Activation Code is unchanged. `--ignorelocal` retains its existing
reset behavior; combine it with `--activation=...` to set a code in fresh state.

Managed-profile Activation Codes still take precedence over the local value.
No code is extracted from an App Token, and no token is fetched by deployment.
The normal deploy flow still requires a configured Jamf URL and restarts the
LaunchDaemon. Full Activation Codes are not written to script logs, but command
arguments and Jamf policy parameters should be treated as administrative data.

Run the isolated deployment-state tests with:

```sh
/bin/zsh Tools/test_deploy_activation.sh
```

Confidential build inputs such as the real Ministry transport implementation are
intentionally not part of the public source tree. Authorized Ministry builds keep
those files below `*.local/` directories.
