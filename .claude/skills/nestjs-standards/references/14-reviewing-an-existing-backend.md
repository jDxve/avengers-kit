## 13. Reviewing an existing backend

Fast pass in this order. Each question usually finds something.

1. **Read, check, write races.** Grep for a `find` followed by an `if` followed by an
   `insert` or `update` on the same entity. Then check whether a unique constraint or an
   atomic conditional write backs it. This is the highest-value check in the list.
2. **IDOR.** Pick three detail endpoints and three mutations. Does each scope the lookup to
   the caller, tenant, or branch, or only check that someone is logged in?
3. **Guarded updates that ignore `rowCount`.** A conditional update whose result is never
   checked is a silent no-op under concurrency.
4. **Unexpectedly public routes.** If auth is global, audit every `@Public()`. If it is not
   global, the routes with no guard are where your breach is.
5. **Refresh-token families.** Can a family hold two live tokens? Check for the partial
   unique index, and check whether reuse is classified by successor state or by a clock
   (4.8). Then run the four tests at the end of 4.8. This is usually where a backend that
   looks correct turns out not to be.
6. **Errors relabelled on the way up.** Grep for `catch` blocks that throw a domain error
   unconditionally. A `TypeError` arriving at the client as a business code hides the bug
   and tells the client to retry it.
7. **Mass assignment.** In a test environment, post `role: "admin"` to a profile update and
   see what happens.
8. **God services.** `wc -l` across `*.service.ts`, sort descending, inspect the top three
   for cohesion.
9. **Business logic in controllers.** Grep for ORM calls and branching in `*.controller.ts`.
10. **`forwardRef`.** Inspect each one and name the cycle behind it.
11. **Unbounded lists.** Grep for `db.select()` or `db.query.<table>.findMany()` with no `.limit()` or `limit`.
12. **External calls inside transactions.** Grep for `fetch`, `axios`, or a mailer inside a
    transaction block.
13. **Webhook signature verified against the raw body**, not a re-serialized object.
14. **Cron in every instance.** Check the process manager config.
15. **Does it start with a missing env var?** If yes, config is not validated.
16. **`console.log`, `any`, empty `catch`.** Grep.

---

