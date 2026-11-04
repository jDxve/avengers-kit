## 1. Principles

1. **Cohesion decides structure.** Group what changes together. Split what changes for
   different reasons.
2. **Controllers are thin.** Routing, guards, DTO binding. Nothing else.
3. **The dependency graph is acyclic.** Domains may depend on each other. They may not form
   cycles.
4. **Explicit over implicit.** Every route declares its guards. Every module declares its
   exports. Public access is marked, never inferred from absence.
5. **The boundary is the contract.** Validate everything entering, shape everything leaving.
   Never return a raw database row.
6. **Correctness under concurrency is a design requirement, not a tuning exercise.** See
   section 6.
7. **If it is hard to test, the design is wrong.** Untestable code is a structural signal.

---

