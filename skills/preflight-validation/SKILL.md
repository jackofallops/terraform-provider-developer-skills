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

> **Typed resources only:** Preflight validation is currently only fully supported for
> resources that use the Typed SDK wrapper (`sdk.Resource`). Native `*pluginsdk.Resource`
> resources require additional wiring not yet implemented. If the target resource is native,
> consider migrating it using the `resource-framework-migration` skill first.

---

## Prerequisites

Before implementing, confirm:

- The resource is a **Typed** resource (implements `sdk.Resource` with a `*Model` struct).
- The resource type is supported by the Azure Preflight Validation API.

---

## Step 1 — Add or update `CustomizeDiff`

Check whether the resource struct already implements `sdk.ResourceWithCustomizeDiff`.

**If it does not**, add the interface compliance assertion and implement the method. See
the `modify-typed-resource` skill for the full pattern. The minimum skeleton is:

```go
var _ sdk.ResourceWithCustomizeDiff = MyResource{}

func (r MyResource) CustomizeDiff() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Timeout: 5 * time.Minute,
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            if metadata.ResourceDiff == nil {
                return nil
            }

            var model MyResourceModel
            if err := metadata.DecodeDiff(&model); err != nil {
                return err
            }

            // preflight call goes here (Step 3)

            return nil
        },
    }
}
```

The SDK wrapper in `sdk/wrapper_resource.go` automatically detects the interface and wires
up `CustomizeDiff` — no changes to the resource registration are needed.

**If it already exists**, add the preflight block inside the existing `Func`, after the
existing `DecodeDiff` call and before any `return` statements.

---

## Step 2 — Extract the expand function

Locate the request payload construction in `Create()`. It will look like:

```go
func (r MyResource) Create() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            var model MyResourceModel
            if err := metadata.Decode(&model); err != nil {
                return err
            }

            params := mypackage.MyResourceType{   // <-- this block is the target
                Location: location.Normalize(model.Location),
                Properties: &mypackage.Properties{
                    SkuName: model.SkuName,
                    // ...
                },
            }

            if _, err := client.CreateThenPoll(ctx, id, params); err != nil {
                return fmt.Errorf("creating %s: %+v", id, err)
            }
        },
    }
}
```

Extract the payload construction into a named function:

```go
func expandCreateForMyResource(model MyResourceModel) (mypackage.MyResourceType, error) {
    return mypackage.MyResourceType{
        Location: location.Normalize(model.Location),
        Properties: &mypackage.Properties{
            SkuName: model.SkuName,
            // ...
        },
    }, nil
}
```

Update `Create()` to call it:

```go
params, err := expandCreateForMyResource(model)
if err != nil {
    return err
}
```

**For Pattern 3 only:** if the update payload is structurally different, extract the update
payload construction from `Update()` into `expandUpdateForMyResource(model MyResourceModel)`.
The function must still return the **complete** PUT body — partial PATCH bodies are not valid
for preflight.

---

## Step 3 — Add the preflight call

### Choosing a pattern

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

### Implementation reference

Full code examples for Patterns 1, 2, and 3 — including the ForceNew detection approach
for Pattern 2 and the `expandUpdateForMyResource` guidance for Pattern 3 — are in:

**[`internal/preflight/README.md`](../../../internal/preflight/README.md)**

### Required structure

Every preflight block must include:

1. A nil guard for `metadata.ResourceDiff` (in the outer `CustomizeDiff` func)
2. A check for `metadata.Client.Features.EnhancedValidation.PreflightEnabled`
3. A change-detection guard (`len(GetChangedKeysPrefix("")) > 0 || Id() == ""`)
4. A call to `expandCreateForMyResource` (or `expandUpdateForMyResource` for Pattern 3)
5. A call to `preflight.NewValidationRequest` followed by `ValidateResource`

---

## DAG context

`CustomizeDiff` runs during `PlanResourceChange`, concurrently across independent resources.
The preflight API validates config shape and Azure Policy — it does **not** check whether
the resource or its dependencies currently exist in Azure. There is no DAG-related ordering
concern with preflight calls.

Values that are `(known after apply)` in the plan — such as outputs of other resources not
yet created — will be zero in the preflight payload. This is a known validation gap (false
negatives), not a false positive risk. See `internal/preflight/README.md` for the full
impact assessment.

---

## Common pitfalls

- Passing a PATCH/partial body to preflight — results in silent under-validation
- Omitting the change-detection guard — causes redundant API calls on unchanged plans
- Omitting the `ResourceDiff == nil` guard — causes a panic during import operations
- Using `expandCreateForMyResource` when the update PUT body is structurally incompatible
  with what the create body expects — use Pattern 3 in this case
