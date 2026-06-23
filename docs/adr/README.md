# Architecture Decision Records (ADRs)

This directory holds architecture decision records for Cortex.app. Format is
lightweight Markdown inspired by [MADR](https://adr.github.io/madr/). Each ADR captures
WHY a decision was made -- the codebase shows WHAT.

## Index

- [ADR-0001 -- Foundation and 2026 Toolchain](0001-foundation-and-2026-toolchain.md)
- [ADR-0002 -- v0 Ship, BCI HID Integration, and the Wire-and-Gate Doctrine](0002-v0-ship-and-bci-hid-integration.md)

## When to write an ADR

Write a new ADR when:

- A decision crosses module boundaries or affects multiple phases
- A decision rejects an obvious-seeming alternative for non-obvious reasons
- A decision encodes a project commitment (e.g., "no `_ANEClient`", "compile-time guarantees beat runtime ones")
- A decision is about a tradeoff that future contributors might second-guess

Do NOT write an ADR for:

- Local refactors or formatting changes
- Standard library/framework usage that follows official patterns
- Decisions that are obvious in hindsight (e.g., "use Swift 6.2 because Xcode 26 ships it")

## ADR template

```
# ADR XXXX -- [Short title]

**Status:** Proposed | Accepted | Superseded by ADR-YYYY | Deprecated
**Date:** YYYY-MM-DD
**Deciders:** @username

## Context

What is the issue? What forces are at play?

## Decision

What did we decide? State it imperatively.

## Consequences

What are the downstream implications? Both positive and negative.

## Alternatives considered (rejected)

What else did we consider? Why did we reject it?
```

## Numbering

ADRs are numbered sequentially (0001, 0002, 0003, ...). Decimal numbers are NOT used --
if a previous ADR is superseded, write a new ADR that references the old one's number
in its "Status" line and update the old ADR's Status to "Superseded by ADR-XXXX".
