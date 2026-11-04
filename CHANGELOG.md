# Kit changelog

Changes to the kit itself. Each standard records its own rule changes.

## 2026-11-04

- Removed the Gemini workflow. Thor builds `ui/` widgets from the contract.
- Set Drizzle and Zod as the fixed stack (ADR-012), with strict request schemas on every nested object.
- Set Riverpod as the Flutter default (ADR-011). `ui/` stays pure whichever library is used.
- Added a `migrate` stage to the NestJS Dockerfile.
- Added visual bug routing to Captain America.
- Fixed hook path handling on Windows, and hooks now run through `bash`.
- Added the no agent attribution rule: commits and pull requests carry only Dave's identity.
