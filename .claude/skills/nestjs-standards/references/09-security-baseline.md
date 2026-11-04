## 8. Security baseline

REQUIRED for every project.

- [ ] Auth guard registered globally, public routes opted out explicitly (4.1)
- [ ] Every non-public route declares its authorization, not just authentication
- [ ] **IDOR checked**: every resource lookup is scoped to the caller's ownership or tenant,
      not merely authenticated. `findById(id)` with no ownership check is the single most
      common real-world breach in CRUD apps
- [ ] Mass assignment blocked (4.3)
- [ ] Auth lifecycle per 4.8, including token verification and revocation behavior
- [ ] CSRF protection wherever the browser attaches credentials automatically (cookie-based
      sessions or refresh tokens). A bearer token read from JS storage does not need it; a
      cookie does, whether or not your frontend sets it deliberately
- [ ] CORS restricted to known origins, no wildcard with credentials
- [ ] Helmet or equivalent security headers
- [ ] Payload size limits set
- [ ] Uploads validated by MIME and size, filenames sanitized, never served from the app root
- [ ] No secrets in the repo; `.env.example` lists every key with no real values
- [ ] Error responses expose no stack traces or SQL
- [ ] Dependency audit clean in CI, or exceptions documented with an expiry date

---

