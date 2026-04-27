---
name: preflight-validation
description: Assist in implementing Azure Preflight Validation in a resource's CustomizeDiff function, including selecting the correct pattern (1, 2, or 3) for the resource's create/update semantics.
triggers:
  - "preflight validation"
  - "CustomizeDiff preflight"
  - "plan time validation"
  - "enhanced_validation preflight_enabled"
---

# Preflight Validation

The AzureRM provider supports plan-time validation of resource configurations via the Azure
Preflight Validation API. This is gated behind the `features.enhanced_validation.preflight_enabled`
feature flag and is implemented in a resource's `CustomizeDiff` function.

## Core constraint

The Azure Preflight Validation API validates **full ARM PUT payloads only**. PATCH operations
are not supported. Any expand function passed to `preflight.NewValidationRequest` must return
the **complete** resource body as it will be sent to the ARM API.

## When to implement

- The resource has a `CustomizeDiff` implementation (or one needs to be added).
- The resource type is supported by the Azure Preflight Validation API.
- The resource has a stable expand function that produces the full ARM body.

## Choosing a pattern

| Question | Pattern |
|---|---|
| Update uses full PUT, same body shape as create | **1** — reuse `expandCreateForMyResource` |
| Want to skip preflight for in-place updates (e.g. resources with immutable fields) | **2** — create + ForceNew only |
| Update uses a different full PUT body than create | **3** — separate expand functions |
| Update uses PATCH | **3** with a dedicated `expandUpdateForMyResource` |

**Pattern 1 is the right default for most ARM resources.** `ResourceDiff` always contains the
complete planned state — unchanged fields on an update are resolved from prior state, so
`expandCreateForMyResource` has all the data it needs regardless of operation type. Pattern 3
is only needed when the create and update PUT bodies are structurally different (e.g. an
immutable field that ARM rejects if re-sent on update), not because data is missing.

## Implementation reference

Full code examples for Patterns 1, 2, and 3 — including the ForceNew detection approach
for Pattern 2 and the `expandUpdateForMyResource` guidance for Pattern 3 — are in:

**[`internal/preflight/README.md`](../../../internal/preflight/README.md)**

## DAG context

`CustomizeDiff` runs during `PlanResourceChange`, concurrently across independent resources.
The preflight API validates config shape and Azure Policy — it does **not** check whether
the resource or its dependencies currently exist in Azure. There is no DAG-related ordering
concern with preflight calls.

## Required structure

Every preflight implementation must include:

1. A nil guard for `metadata.ResourceDiff`
2. A check for `metadata.Client.Features.EnhancedValidation.PreflightEnabled`
3. A change-detection guard (`len(GetChangedKeysPrefix("")) > 0 || Id() == ""`)
4. An expand function producing the **complete** ARM PUT body
5. A call to `preflight.NewValidationRequest` followed by `ValidateResource`

## Common pitfalls

- Passing a PATCH/partial body to preflight — results in silent under-validation
- Omitting the change-detection guard — causes redundant API calls on unchanged plans
- Omitting the `ResourceDiff == nil` guard — causes a panic during import operations
