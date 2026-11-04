## 7. Accessibility

REQUIRED for every project. Not a later pass, and not a specialist's job.

- [ ] Semantic elements first: `button`, `a`, `nav`, `main`, `ul`, `table`, `label`. ARIA is
      for what semantics cannot express, and a wrong ARIA attribute is worse than none
- [ ] Everything interactive is reachable and operable by keyboard: Tab, Enter, Space,
      Escape, and arrow keys where a widget implies them
- [ ] A visible focus indicator everywhere. Never `outline: none` without a replacement
- [ ] Every input has a programmatically associated label. Placeholder text is not a label;
      it disappears as soon as the user types
- [ ] Validation errors are associated with their input (`aria-describedby`) and announced
      to assistive technology, not only colored red
- [ ] Focus is managed on navigation and in overlays: a dialog takes focus, traps it, closes
      on Escape, and returns focus to whatever opened it
- [ ] Text contrast at least 4.5:1, and 3:1 for large text and meaningful icons
- [ ] Information is never carried by color alone. Add a label, icon, or pattern
- [ ] Images have meaningful `alt`, or `alt=""` when decorative. Never a filename
- [ ] Headings form a real outline, one `h1` per page, no levels skipped for styling
- [ ] Zoom to 200% and 400% without content loss or horizontal scrolling of the page
- [ ] `prefers-reduced-motion` respected for transitions and autoplay
- [ ] Live regions for async status, so a screen reader hears "saved" and "3 results"
- [ ] Tested with the keyboard alone, and once with a screen reader on the primary flow

**DEFAULT.** Use a tested primitive library (Radix, React Aria) for dialogs, menus, tabs,
comboboxes, and tooltips. Correct focus management and ARIA for these is a large job that
is already done well elsewhere, and hand-rolled versions are where accessibility bugs live.

---

