## 14. When to outgrow this

This standard covers a single React application organized by feature, which is the right
answer for most products and nearly all teams under ten engineers. Signals that you need
more:

- **The design system is consumed by more than one app.** Extract it into its own versioned
  package with its own tests and release process. Before that, a folder is better.
- **Several apps share domain logic and types.** A monorepo with shared packages earns its
  tooling cost here, and not before.
- **A flow has enough states and illegal transitions that bugs keep shipping.** Model it
  explicitly with a state machine, for that flow only.
- **Teams with separate release cadences own separate parts of one page.** Only then
  consider module federation or micro-frontends, and know that you are trading a build
  problem for a runtime problem.
- **Rendering strategy is the bottleneck.** Measure first, then move work to the server,
  stream it, or pre-render it. Do not adopt a rendering architecture because it is current.

Do not adopt any of these because the architecture looks plain. A feature-organized app with
a query layer, enforced boundaries, real tests on critical flows, and an accessible keyboard
path beats an elaborate architecture with none of those.

---

