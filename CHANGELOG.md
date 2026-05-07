# Changelog

All notable changes to the `assinafy` Ruby gem are documented here.

## Unreleased

### Added

- Documented authentication resource: login, social login, API key, and password flows.
- Documented field definition resource.
- Documented signer-access-code and signer document flows.
- Document status, public document info, and signer token helpers.

### Changed

- Removed undocumented workspace CRUD from the SDK surface.
- Simplified signer creation to call the documented create endpoint directly.
- Multipart uploads no longer inherit a global JSON `Content-Type` header.
- Query/body key normalization now maps only documented hyphenated fields.

### Removed

- Docker Compose test harness and committed vendored bundle from the SDK repository.
