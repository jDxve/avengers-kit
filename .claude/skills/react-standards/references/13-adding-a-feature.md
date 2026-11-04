## 12. Adding a feature

1. Does it belong in an existing feature? If it has its own routes, its own API surface, and
   its own vocabulary, it is a new feature folder.
2. Classify the state before writing any (4.3). What is server state, what belongs in the
   URL, what is form state, what is genuinely local. Getting this wrong is the expensive
   mistake, and it is cheap to get right first.
3. Generate or confirm the API types, and define the Zod schemas for requests, responses,
   and forms.
4. Write the queries and mutations in `features/<name>/api/`, with structured query keys and
   the invalidations each mutation owes.
5. Put business rules in `features/<name>/lib/` as pure functions. Put stateful logic in
   hooks. Keep components rendering.
6. Build the component with all four states from the start, composing from `components/ui/`.
   Pure rendering may go in `features/<name>/ui/`, with a connected parent passing values and
   callbacks (4.1).
7. Make it keyboard operable and labelled as you build it, not afterwards (section 7).
8. Export only what other features need from `index.ts`.
9. Test: the pure functions, the four states, and any async race from section 6 the feature
   introduces.
10. Check the bundle diff if you added a dependency.

---

