---
description: Direct App Store Connect automation using App Store Connect API JWT auth for metadata and screenshots, plus xcrun altool for binary upload
---
# Direct App Store Connect API + altool release workflow

Use this workflow when you want to automate App Store Connect work without browser/UI automation and without adding fastlane.

## Authoritative path

- Use **App Store Connect API** for app lookup, version lookup, localization metadata, screenshot sets, screenshot asset reservations, screenshot upload commit, and release-related resource updates that are supported by Apple’s REST API.
- Use **`xcrun altool`** for app binary validation/upload when using the local Apple upload tooling path.
- Keep one API auth source of truth:
  - `key_id`
  - `issuer_id`
  - `.p8` private key path

## Required inputs

For this repository, the current auth values are:

- `key_id`: `KS8L66PG43`
- `issuer_id`: `9e48801a-8319-48b9-994a-84b06bd86f86`
- `p8_path`: `/Volumes/waffleman/chentoledano/Projects-new/focus-timer/.creds/AuthKey_KS8L66PG43.p8`

Other required release inputs:

- `bundle_id`: `com.5minutesblockstimer`
- localized metadata text:
  - subtitle
  - promotional text
  - description
  - keywords
- screenshot directory:
  - `/Volumes/waffleman/chentoledano/Projects-new/focus-timer/screenshots/cropped-more-top`
- archive or `.ipa` path for build upload

## Official references

- Apple Help: Upload builds
  - https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Apple Help: Upload app previews and screenshots
  - https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- Apple docs: App Screenshots
  - https://developer.apple.com/tutorials/data/documentation/appstoreconnectapi/app-screenshots.md
- `altool` man page
  - https://keith.github.io/xcode-man-pages/altool.1.html

## JWT auth for App Store Connect API

App Store Connect API calls require a short-lived JWT signed with the `.p8` key.

JWT header:

```json
{
  "alg": "ES256",
  "kid": "KS8L66PG43",
  "typ": "JWT"
}
```

JWT payload:

```json
{
  "iss": "9e48801a-8319-48b9-994a-84b06bd86f86",
  "aud": "appstoreconnect-v1",
  "exp": <unix timestamp no more than 20 minutes ahead>
}
```

Sign with ES256 using the `.p8` private key.

Authorization header for API requests:

```text
Authorization: Bearer <jwt>
```

Base API URL:

```text
https://api.appstoreconnect.apple.com/v1
```

## Resource lookup sequence

Trace the live data flow in this exact order.

### 1. Find the app

Query apps by bundle id.

Example:

```text
GET /v1/apps?filter[bundleId]=com.5minutesblockstimer
```

Record:

- `app_id`

### 2. Find the target app store version

List app store versions for the app.

Example:

```text
GET /v1/apps/{app_id}/appStoreVersions
```

Pick the target iOS version for release.

Record:

- `app_store_version_id`

### 3. Find the localization for the target locale

List localizations for the version.

Example:

```text
GET /v1/appStoreVersions/{app_store_version_id}/appStoreVersionLocalizations
```

Pick locale `en-US` unless you are intentionally editing another locale.

Record:

- `localization_id`

## Metadata update path

Update the app store version localization resource.

Fields typically include:

- `description`
- `keywords`
- `promotionalText`
- `subtitle`

Use:

```text
PATCH /v1/appStoreVersionLocalizations/{localization_id}
```

Expected body shape pattern:

```json
{
  "data": {
    "id": "<localization_id>",
    "type": "appStoreVersionLocalizations",
    "attributes": {
      "description": "...",
      "keywords": "...",
      "promotionalText": "...",
      "subtitle": "..."
    }
  }
}
```

Do not send guessed attribute names. Confirm the localization resource schema before patching.

## Screenshot upload path

Apple’s screenshot API is not a one-shot file upload. Use the authoritative multi-step flow.

### 1. Find or create screenshot set for locale + display target

List existing screenshot sets for the localization:

```text
GET /v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets
```

If the required display target does not exist, create it.

Use:

```text
POST /v1/appScreenshotSets
```

The request must associate the set to the localization and specify the display target Apple expects for the screenshots you are uploading.

Record:

- `app_screenshot_set_id`

### 2. Create screenshot asset reservation

For each screenshot file:

```text
POST /v1/appScreenshots
```

This creates the screenshot resource and returns upload instructions / upload operations.

The appScreenshots docs state the flow is:

- create screenshot resource
- receive upload operations
- upload bytes to the provided reservation target(s)
- commit with a PATCH on the screenshot resource

Record for each file:

- `app_screenshot_id`
- upload operations

### 3. Upload bytes to reserved upload operation endpoints

Execute each returned upload operation exactly as Apple specifies.

Important rules:

- use the HTTP method Apple returns
- send the exact headers Apple returns
- send the binary bytes of the image file
- do not invent alternate upload URLs

### 4. Commit the screenshot

After upload succeeds, commit it:

```text
PATCH /v1/appScreenshots/{app_screenshot_id}
```

Use the resource state Apple expects for upload completion.

### 5. Repeat for all screenshots

Current screenshot directory for this app:

- `/Volumes/waffleman/chentoledano/Projects-new/focus-timer/screenshots/cropped-more-top`

Current files:

- `photo_2026-03-22 02.07.01.jpeg`
- `photo_2026-03-22 02.07.05.jpeg`
- `photo_2026-03-22 02.07.06.jpeg`
- `photo_2026-03-22 02.07.08.jpeg`
- `photo_2026-03-22 02.07.10.jpeg`

Apple help currently states screenshots can be uploaded as:

- `.jpeg`
- `.jpg`
- `.png`

and requires between 1 and 10 screenshots.

## Binary upload path with altool

Apple help states that `altool` supports upload for app binaries.

If uploading an archive/package with API-key auth, use the current `altool` syntax and verify against the local man page because flags may differ slightly by Xcode version.

Relevant patterns from the local docs/man page:

- validate/upload commands support API key auth
- JWT can be generated via `altool --generate-jwt`
- `--apiKey` and `--apiIssuer` are supported

Typical command pattern:

```bash
xcrun altool --upload-package <file> \
  --platform ios \
  --apiKey KS8L66PG43 \
  --apiIssuer 9e48801a-8319-48b9-994a-84b06bd86f86
```

Or depending on artifact type/Xcode behavior:

```bash
xcrun altool --upload-app -f <file> -t ios \
  --apiKey KS8L66PG43 \
  --apiIssuer 9e48801a-8319-48b9-994a-84b06bd86f86
```

Before upload, validate the exact accepted command form against the installed `xcrun altool --help` output.

## Recommended execution order

1. Generate JWT for App Store Connect API.
2. Resolve `app_id` from bundle id.
3. Resolve `app_store_version_id` for the live target version.
4. Resolve `localization_id` for `en-US`.
5. PATCH localization metadata.
6. Resolve or create screenshot set for the target display size.
7. Upload screenshots using the asset reservation flow.
8. Upload build with `altool` if the build is not already present.
9. Attach the build to the target version if needed via API-supported resource relationships.
10. Only after all required assets are present, proceed to submission-related API steps that Apple supports.

## Fail-fast checks

Do not proceed if any of these are missing:

- missing `app_id`
- missing target `app_store_version_id`
- missing `localization_id`
- missing screenshot set target choice
- missing upload operations for a screenshot reservation
- missing build artifact path for binary upload

Throw explicit errors instead of guessing fallback IDs or alternate resource names.

## Known unknowns to verify before live mutation

These must be confirmed from the live API schema/response before mutating production state:

- exact `appStoreVersionLocalization` patchable attribute names returned by current API
- exact screenshot set display type value for the desired iPhone screenshot slot
- exact request body for `POST /v1/appScreenshotSets`
- exact commit body for `PATCH /v1/appScreenshots/{id}`
- whether the current build is already uploaded and only needs attachment
- exact submission endpoint/resource needed for final review submission in the current API

## Definition of done

This workflow is complete only when:

- metadata is updated via API
- screenshot set exists for the target localization/display type
- all required screenshots are uploaded and processed
- build is uploaded or already attached
- the app version is ready for review submission using supported Apple interfaces
