---
trigger: always_on
---

# Anti-Residue Rule

## Core Principle
Deletion first. Not more helperization. Not more wrappers. Not more backward-compatibility layers by default.

## Forbidden Anti-Pattern
Never do this sequence:

1. Add a new branch
2. Add a retry layer
3. Add a helper for the retry
4. Keep the old path too
5. Preserve backward compatibility by default
6. Skip the deletion pass
7. Repeat

This pattern causes:
- branch growth
- helper growth
- argument growth
- schema growth
- prompt/runtime glue growth
- bloated files full of "still supported for now"

## Mandatory Rule
When changing a central code path, the agent MUST:

1. Trace the full live data flow first
2. Identify the single current authoritative path
3. Identify all old, parallel, fallback, retry, compatibility, and versioned paths
4. Delete superseded paths in the same change
5. Delete dead flags, dead schema fields, dead compatibility args, and dead helper layers
6. Keep exactly one authoritative contract per concern

## Backward Compatibility Rule
Backward compatibility is NOT allowed by default.

It is only allowed if the agent can prove there is a live consumer that still depends on the old contract.

If that proof is missing:
- delete the old path
- delete the old flag
- delete the old schema shape
- delete the old helper

## Helper Rule
Helpers are allowed only if they simplify the single surviving path.

Helpers are NOT allowed if they:
- preserve obsolete flow
- hide duplicate behavior
- wrap dead compatibility logic
- exist only to keep old and new systems alive at the same time

## Branch Rule
Every new branch must answer:
- what old branch is being replaced?
- where is that old branch deleted in this same change?

If there is no deletion, the change is incomplete.

## Retry Rule
Retry logic is allowed only if it is part of the current authoritative contract.

Retry logic is residue if it exists to patch over:
- old schema versions
- old payload shapes
- old prompt contracts
- old runtime contracts
- temporary rollout compatibility that was never removed

## Schema Rule
For every concern, keep one authoritative schema only.

If the code accepts multiple names, shapes, or versions for the same concept, that is residue unless a live consumer is explicitly proven.

## Refactor Rule
A refactor is NOT complete if it only moves duplication into helpers.

A refactor is complete only when it:
- deletes obsolete paths
- deletes old arguments
- deletes dead flags
- deletes compatibility branches
- reduces the number of live concepts

## Definition of Done
A central path is considered clean only if all of the following are true:
- one authoritative execution path
- one authoritative schema per concern
- no parallel legacy path
- no dead toggles
- no dead retries
- no dead wrappers
- no helper whose only purpose is preserving obsolete behavior
- no "still supported for now" code without explicit proof of a live consumer

## Required Agent Behavior
Before ending any architecture/refactor task, the agent must explicitly state:
- the authoritative path
- what residue was deleted
- which old branches/flags/helpers were removed
- what still remains and why

If the agent cannot name what was deleted, then the cleanup is not done.