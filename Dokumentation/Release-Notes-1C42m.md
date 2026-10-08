# Notary 2.2 Beta - 1C42m

Early public beta of the 1C development line. Please test on a small managed
device group before wider deployment.

## Highlights

- **Ministry Licensing Service:** Notary checks in with
  `https://license.ministryofcode.de` using the configured Activation Code and
  a pseudonymous Machine Identifier. Returned App Tokens are verified locally
  before being securely cached. Subsequent requests send the cached Token ID
  and actual Token Version.
- **Offline support:** A valid cached App Token remains usable when the server
  cannot be reached. Confirmed license rejections disable optional licensed
  features and remain effective across restarts. Local compliance evaluation
  remains independent of licensing-server availability.
- **Menu-bar history:** Compact three-minute graphs show network receive
  (green), network send (red), and combined CPU activity (blue). Compliance
  status remains the primary visual signal.
- **XProtect:** Regular evaluation resumes on macOS 27.2 and later. The
  workaround remains limited to affected macOS 27.0/27.1 versions, where the
  check is reported as `SKIP`.
- **Stability and performance:** Reliability improvements to token persistence,
  offline handling, and feature-state updates, together with a restrained
  three-second sampling interval for menu-bar history.

## Beta Setup

- Configure the Activation Code through the managed configuration profile or
  existing local configuration. This early beta deliberately does **not**
  extract or save an Activation Code from an existing App Token.
- Allow outbound HTTPS access to `license.ministryofcode.de`.
- License records and feature flags must be maintained on the Licensing Service.
  Once a server-issued token is accepted, its feature flags take precedence
  over an older token supplied through a profile.
- Activation-Code deployment through the policy script and a local activation
  dialog are not part of this beta.
- Compliance details are not sent to the Licensing Service. Machine identity
  is pseudonymous; the raw hardware UUID is not transmitted.

## Distribution

The installer was built locally with the complete internal Ministry modules
for Report, Config, and Transport. GitHub source archives contain the public
source tree with dummy Transporter and Reporter implementations, not the
confidential implementation sources.

Package: `notary-2.2-1C42m.pkg`

- Developer ID signature: valid
- Apple notarization: Accepted
- Stapled notarization ticket: valid
- Gatekeeper: accepted (`Notarized Developer ID`)
- SHA-256: `0be393d1a396efe46a516a37e3ae3ed4195ed6e0e29e706ffd154d06f96f628f`

## Verification

App Token tests, transport regression tests, and licensing cache tests passed.
The isolated Docker integration test verified token issuance, unchanged-token
responses, feature changes, license rejection, and recovery.
