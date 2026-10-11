# Notary 2.2 Beta - 1C44k

Complete internal build on the `k` beta channel. This beta targets extended
Display-Off and Sleep/Wake testing, especially on unattended build agents.
Deploy to a managed test group before wider rollout.

## Changes Since 1C42m

- **Background state access:** The private Notary state file now uses Data
  Protection Class C (`CompleteUntilFirstUserAuthentication`) instead of
  `CompleteUnlessOpen`. On macOS this class uses a key available while the
  volume is mounted. Existing state is migrated under the file lock before
  each cycle, without deleting or replacing its contents. Both the runner
  and Extension Attribute writer retain the same protection class and private
  root-owned `0600` permissions.
- **Clearer diagnostics:** A failure to read the state file is reported as a
  read error, not incorrectly as a plist decode failure. An inaccessible
  state still aborts the cycle: Notary does not substitute empty credentials
  or manufacture fresh compliance or successful-contact timestamps.
- **Modern MacBook detection:** Notebook detection uses built-in lid hardware
  for modern `Mac...` model identifiers. Hibernate evaluation no longer skips
  these MacBooks as desktop machines. An undetermined hardware type yields
  `unknown`, with no enforcement changes made for that condition.
- **Activation Code deployment:** `Tools/deploy.sh` supports
  `--activation=NOTX...` to save the local Activation Code while preserving
  existing token/cache and configuration data. Managed profile values retain
  precedence. Without the option, the existing local code is preserved.
- **Check scheduling groundwork:** Execution classes 0 through 5 and retry
  metadata are documented in the check registry. This is preparation only:
  parallel execution, cached once-per-start results and the new scheduling
  intervals are not activated in this beta.
- **App Token compatibility:** Tests verify that additional signed device
  identity fields are accepted by the existing validator and remain covered
  by signature verification. This does not introduce client-side enforcement
  of device binding.

## Retained 2.2 Features

- Ministry Licensing Service check-in using the configured Activation Code
  and pseudonymous Machine Identifier, with locally verified App Token caching.
- Valid offline token fallback on network, TLS or server failures; confirmed
  license rejections continue to restrict optional features. Local compliance
  evaluation remains independent of licensing-server availability.
- Compact three-minute network and CPU history in the menu-bar status view.
- Regular XProtect evaluation on macOS 27.2 and later; `SKIP` remains limited
  to affected macOS 27.0/27.1 versions.
- Existing Report, Configurator and Transport functionality remains included.
  Reporter and Configurator are feature-frozen pending a tested standalone
  Admin replacement; they are not removed or disabled in this beta.

## Required Field Test: Cocoa 257

The observed transient `NSCocoaErrorDomain Code=257` / POSIX `EPERM` state-file
read failure has occurred on two test Macs, including after a macOS update.
The former protection class was confirmed on the development Mac. The change
in this beta is a candidate mitigation, not a confirmed resolution of the
macOS-specific behavior.

Test Display-Off, screen lock, actual system sleep and wake separately.
Display-Off is not system sleep. Notary cannot execute during actual system
sleep, but may execute while the display is off or during a background wake.
This release does not prevent sleep or artificially keep machines awake.

On build agents, observe several prolonged Display-Off periods and verify:

- Successful local cycles and Licensing Service check-ins continue while
  the machine remains awake with its display off.
- The next eligible cycle after waking resumes without repeated state access
  failures. No new wake-triggered scheduler is introduced.
- Existing Activation Code, cached App Token and Jamf settings survive the update.
- Jamf Last Contact advances only after successful Jamf transport, not merely
  after local evaluation or Licensing Service check-in.

Correlate failures with power-management timestamps. Do not include App Tokens,
Jamf credentials or the complete private state file in bug reports.

Apple's documented macOS Class-B boundary is login/logout, not simply screen
lock. Therefore the sleep-related root cause still requires field validation.
[Apple Data Protection classes](https://support.apple.com/guide/security/secb010e978a/web).

## Deployment

Keep the existing managed configuration or deploy the Activation Code with
the updated policy script. This beta still does not automatically extract and
persist an Activation Code from an existing App Token.

Allow HTTPS access to `license.ministryofcode.de`. No Licensing Service update
is required for the state-file change. Compliance details are not uploaded
to the Licensing Service; raw hardware UUIDs are not transmitted.

## Distribution

The attached installer is built with the complete internal Report, Config
and Transport implementations. GitHub source archives retain the public dummy
Reporter and Transporter implementations; confidential sources are not published.

Package: `notary-2.2-1C44k.pkg`

SHA-256: `afaa89a532e554af10dedd08adb640ecb9c10bf0a524bbc1ec9d6e2ed377757e`

## Verification

Transport, licensing-cache, App Token, hardware classification, check-policy
metadata and deploy-script activation regression tests passed. State tests
cover Class-B-to-Class-C migration with unchanged file contents, private
permissions after both write paths, retained state values, and separate
read/decode errors. Isolated Licensing Service integration passed using
disposable test credentials, never a production license or Jamf account.

The installer is Developer ID signed, accepted by Apple's notarization service,
and stapled. Stapler validation and Gatekeeper installation assessment passed.

These automated tests do not replace the prolonged Display-Off/Sleep/Wake
field test described above.
