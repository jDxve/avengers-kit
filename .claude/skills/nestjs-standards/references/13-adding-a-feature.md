## 12. Adding a feature

1. Does it belong in an existing domain? If it needs its own tables and its own guards, it
   is a new module.
2. Model the data. Name the invariants, then pick the concurrency mechanism for each from
   the table in section 6. Add unique constraints for anything that must not duplicate.
   Generate the migration with `drizzle-kit generate` and commit it.
3. Define the request and response Zod schemas and their `createZodDto` classes.
4. Put the logic in a service: extend a cohesive existing one, or add a new one if the
   responsibility is genuinely different (4.2).
5. Add the route with its guard stack, scoped to the caller's ownership.
6. Register in the module. Add to `exports` only if another module needs it.
7. Test the logic, the ownership check, and any concurrency guard.
8. Regenerate OpenAPI. Update the docs.

---

