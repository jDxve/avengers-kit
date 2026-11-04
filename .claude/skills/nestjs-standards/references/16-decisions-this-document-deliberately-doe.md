## 15. Decisions this document deliberately does not make

This standard says how to build. It does not invent your numbers or your policies. Record
these per project, in the repo, and keep them current:

- **Auth:** access-token lifetime, refresh-token lifetime, where the client stores tokens,
  **whether lost-response recovery is Strict or Recoverable (4.8)**, the worst-case
  revocation exposure window, signing-key rotation, and account recovery.
- **Authorization:** the role or permission model, the tenant/branch/resource boundaries,
  and what ownership means for each resource.
- **Data:** the authoritative money representation, the timezone and calendar rules, the
  retention and deletion policy, what must be audited, and which invariants are enforced by
  a constraint or a lock (section 6).
- **Reliability:** the availability target, per-dependency timeout budgets, retry ceilings,
  and recovery time and recovery point objectives if anyone has committed to them.
- **Operations:** deployment topology and instance count, who owns migrations, who owns
  backup and restore and how often it is tested, who receives alerts, and the rollback or
  forward-fix procedure.
- **API compatibility:** which versions are supported, the deprecation window, and the
  client compatibility policy.
- **Privacy:** what counts as personal data here, what is minimized, who may access it, how
  long it is kept, and what is redacted from logs.

If one does not apply, write down why. If one is unknown, mark it unresolved rather than
quietly picking a value, because an unresolved decision someone can see is safer than a
default nobody chose.