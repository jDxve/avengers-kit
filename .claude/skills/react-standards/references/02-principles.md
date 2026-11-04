## 1. Principles

1. **Server state is not client state.** Data that lives on a server is a cache locally.
   Treat it as one, with a library built for it, and never copy it into component state.
2. **State lives at the level that owns it.** URL state in the URL, form state in the form,
   server state in the query cache, ephemeral UI state in the component. Most "global state"
   problems are state stored in the wrong place.
3. **Components render; they do not decide.** Business rules belong in pure functions,
   stateful logic in hooks, and both are testable without a renderer.
4. **The dependency graph is acyclic.** Features may depend on shared layers. They may not
   form cycles, and they may not reach into each other's internals.
5. **Accessibility and the error state are part of the feature.** A component that works for
   a mouse user on a fast network with valid data is roughly a third finished.
6. **Measure before optimizing.** `memo`, `useMemo`, and `useCallback` are not free and are
   usually noise. Find the slow render before you spend complexity on it.
7. **The client enforces nothing.** Validation, permissions, and limits are user experience
   here and security on the server. Assume a user who edits the bundle.
8. **If it is hard to test, the design is wrong.** A component you can only test by clicking
   through three screens is holding logic that should have been extracted.
9. **A rule that is not executable is advice.** Anything in sections 3, 4, 7, and 9 that a
   machine can check is checked in CI, and the checker is itself tested against fixtures
   that must fail. Section 11 is where this lives, and it is the section that makes the
   rest of the document real.

---

