# ADR-010: Purely visual state in `ui/` widgets

Status: accepted

## Context

`ui/` widgets are stateless, but some rendering cannot be: an animation controller, a text editing controller, a focus node, an expanded or hovered flag.

## Decision

A `ui/` widget may hold state that is purely visual and lost harmlessly on rebuild. It suppresses the lint with a line citing this ADR and saying what the state is.

Never allowed: a copy of data from parameters, a loading or error flag, a selection the app needs to know about, or anything sent to a server. Those belong in the notifier or query layer.

## Cost

Reviewers check each suppression, because no machine can tell visual state from business state.
