# Notary 2.2 - 1C45

Released October 14, 2026. Stable release, without a beta channel suffix.

## Activation and Licensing

- Notary checks in with the Ministry Licensing Service using a configured
  Activation Code and a pseudonymous Machine Identifier. The Activation Code
  identifies the customer; the signed App Token authorizes optional features.
- New server-issued App Tokens are validated locally before being stored
  atomically in the existing private state file. Token ID and version are
  retained so subsequent check-ins can confirm the current token.
- A locally valid cached token remains available during network, TLS or server
  failures, until its signed expiry. Confirmed license rejections are retained
  across restarts and restrict optional features; connectivity failures do not
  create a new license rejection. Local compliance evaluation remains independent
  of licensing-server availability.
- Managed configuration takes precedence for the Activation Code. The public
  `Tools/deploy.sh` also supports `--activation=NOTX...`, preserving existing
  tokens and state. Without that option, the existing local code is preserved.
- A server-issued token for the configured code takes precedence over an older
  profile token. The GUI uses the runner's checked feature projection.
- Licensing check-ins do not upload compliance findings or raw hardware UUIDs.
  Device counts are observational, not seat enforcement in Notary.

## Menu-Bar Metrics

- Compact three-minute network history, with received traffic in green and
  sent traffic in red.
- Separate blue CPU history, with spacing that keeps the headings and charts
  distinct. The compliance state remains the dominant signal.
- Metrics are informational and do not change compliance or authorization.

## macOS Compatibility and Stability

- Regular XProtect evaluation is restored on macOS 27.2 and later. The
  `xprotect check` workaround remains limited to affected macOS 27.0/27.1
  versions, where the check is reported as `SKIP`.
- Modern MacBook models are classified using built-in lid hardware rather than
  relying solely on the legacy `MacBook...` model prefix. Hibernate checks no
  longer incorrectly skip these notebooks as desktop Macs. An undetermined
  hardware type returns `unknown` without changing power settings.
- Private state uses Data Protection Class C and remains root-owned with `0600`
  permissions. Existing state is migrated under the file lock before a cycle
  without replacing its contents; both runner and Extension Attribute write
  paths retain the same protection and permissions.
- Read errors are distinguished from plist decode errors. If state access fails,
  the cycle still aborts rather than substituting empty credentials or publishing
  a fresh compliance/contact state.
- No renewed Cocoa-257 state-access failures have been reported by the operator
  on the test devices and build agents since the 1C44k rollout. This is positive
  field evidence, not a claim that every sleep-related macOS issue is resolved.
- Stability and performance improvements focus on reliable background state
  access and avoiding unnecessary remote transport. Notary does not prevent sleep;
  no execution is expected during actual system sleep. Display-Off and background
  wake must be distinguished from full system sleep.

## Existing Functions and Compatibility

- Existing local reports, Configurator, Jamf Reporter and Transport remain included
  in the complete installer. No existing module is removed by this release.
- Jamf `Notary Last Contact` continues to advance only after successful Jamf
  reporting, not after local evaluation or Licensing Service contact. Existing
  transport change detection, heartbeat and retry behavior remain unchanged.
- Directly distributed App Tokens remain supported during migration. They are
  planned for deprecation in 2.3 and removal in 3.0, not in 2.2.
- Notary does not automatically extract and persist an Activation Code from an
  existing token in this release. Configure it through a managed profile or the
  deployment script to enable server check-in. Without a configured code, the
  check-in is skipped and the existing token path remains available.
- Additional signed device-identity payload fields remain compatible with the
  token validator and covered by signature verification. Client-side enforcement
  of device binding is not introduced by this release.

## Known Limitations

- Security Agent detection can occasionally time out. The existing fallback keeps
  the most recent successful PASS for at most one hour, measured from the actual
  successful check, not refreshed by repeated timeouts. It does not override a
  completed negative result. A 24-hour extension is not implemented.
- Check execution classes and retry metadata are registry groundwork only.
  Parallel checks and the proposed once-per-start/hourly/daily scheduling are
  not activated in 2.2. Existing execution behavior is preserved.

## Deferred to 2.3

- Standalone Notary Admin with Reporter and Configurator; the existing modules
  remain feature-frozen in Notary until a tested replacement is available.
- Token Escrow Service / Jamf Token Broker with customer-scoped Reporter access,
  server-held Jamf credentials and short-lived client access tokens. This is not
  included in 2.2. The API must reject credential storage without explicit
  customer-authorization confirmation.
- Licensing Admin database backup and tested recovery remain prerequisites for
  public Reporter delivery. Setup and direct configuration publishing to Jamf
  remain later roadmap items, not changes to this installer.

## Upgrade

Install the signed package over the existing deployment. Existing state, tokens,
Activation Code and Jamf configuration are retained; state protection migration
occurs on the next runner cycle. Allow HTTPS access to
`https://license.ministryofcode.de` when enabling the Licensing Service workflow.

Use the existing managed configuration, or update the Jamf deployment policy
with `Tools/deploy.sh --activation=NOTX...` as appropriate. Existing configurations
do not need to be recreated merely to install this release. No Licensing Service
or Jamf API contract change is required by this package.

## Distribution and Verification

Installer: `notary-2.2-1C45.pkg`.

SHA-256: `6205397c4faba4e93d307f56ea4ce2435897401d76998370dd79fa0b533a6c5b`.

The installer is built with the full internal Report, Config and Transport
implementations. Public GitHub sources retain the dummy Reporter and Transporter;
confidential source code, private keys and deployment credentials are excluded.

Transport, licensing/cache, App Token, hardware detection, state protection,
check-policy metadata and deployment regression tests passed on the release build.
An isolated Docker integration test against the Licensing Service also passed,
using disposable test credentials and a test signing key, not production data.
The installer is Developer ID signed, accepted by Apple's notarization service
and stapled. Stapler validation, installer signature verification and Gatekeeper
installation assessment passed.
