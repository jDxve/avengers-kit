## 14. When to outgrow this

This standard covers a modular monolith, which is the right answer for most systems and
nearly all teams under ten engineers. Signals that you need more:

- **A domain's rules are complex enough that they belong outside the framework.** Introduce
  a pure domain layer with no Nest or ORM imports, and keep services as the layer that wires
  it. This is where hexagonal architecture earns its cost.
- **Reads and writes have genuinely different shapes and scaling needs.** Consider CQRS, for
  that domain only, not globally.
- **Two parts of the system have incompatible deployment or scaling requirements, and
  separate teams own them.** Only then consider splitting a service out.

Do not adopt any of these because the architecture looks plain. A clean modular monolith
with enforced boundaries, real tests on critical workflows, and correct concurrency handling
beats a distributed system that has none of those.

---

