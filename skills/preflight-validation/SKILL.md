---
name: preflight-validation
description: "[AzureRM-specific] Assist in implementing Azure Preflight Validation in a resource's CustomizeDiff function, including selecting the correct pattern (1, 2, or 3) for the resource's create/update semantics."
triggers:
  - "preflight validation"
  - "CustomizeDiff preflight"
  - "plan time validation"
  - "enhanced_validation preflight_enabled"
---

# [AzureRM-specific] Preflight Validation

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

### Location Fallback and Dependency Lookups

If the resource must fetch a parent or dependency to discover its location (e.g., from an uncreated Virtual Network), you must implement the provider-level location fallback before aborting the preflight check. 

To keep `CustomizeDiff` clean and readable, extract complex dependency lookups and fallback logic into a dedicated helper function (e.g. `resolvePreflight[Dependency]Location(...) (loc string, skip bool, err error)`).

Example helper:
```go
// resolvePreflightVnetLocation determines the Virtual Network location used for preflight
// validation. It returns skip=true when validation should be gracefully skipped (e.g. the
// subnet_id is not yet known, or the Virtual Network doesn't exist and no location fallback
// is configured).
func resolvePreflightVnetLocation(ctx context.Context, metadata sdk.ResourceMetaData, model MyResourceModel) (vnetLoc string, skip bool, err error) {
    // ... basic ID parsing ...

    vnet, err := metadata.Client.Network.VirtualNetworks.Get(ctx, vnetId, virtualnetworks.DefaultGetOperationOptions())
    if err != nil {
        if !response.WasNotFound(vnet.HttpResponse) {
            return "", false, fmt.Errorf("retrieving Virtual Network %%q for preflight validation: %%+v", vnetId.ID(), err)
        }

        // The VNet doesn't exist yet, so we can't determine its location. Rely on the configured
        // fallback if one is available, otherwise gracefully skip preflight validation.
        fallback := metadata.Client.Features.EnhancedValidation.LocationFallback
        if fallback == nil {
            metadata.Logger.Info(fmt.Sprintf("skipping preflight validation for %%q: Virtual Network %%q not found and no location fallback configured", model.Name, vnetId.ID()))
            return "", true, nil
        }

        metadata.Logger.Info(fmt.Sprintf("Virtual Network %%q not found, relying on location fallback for preflight validation", vnetId.ID()))
        return *fallback, false, nil
    }

    if vnet.Model == nil || vnet.Model.Location == nil {
        return "", false, fmt.Errorf("determining Location from Virtual Network %%q for preflight validation: `location` was missing", vnetId.ID())
    }

    return *vnet.Model.Location, false, nil
}
```

Usage in `CustomizeDiff`:
```go
vnetLoc, skip, err := resolvePreflightVnetLocation(ctx, metadata, model)
if err != nil {
    return err
}
if skip {
    return nil
}
```

---

## Step 4 — Add Preflight Acceptance Test

Every resource implementing preflight validation must include an acceptance test verifying that the preflight logic successfully handles a configuration during the plan phase without errors.

1. Add a test function named `TestAcc[ResourceName]_completePreflightPlan`.
2. Configure the test step with `PlanOnly: true` and `ExpectNonEmptyPlan: true`.
3. Create a Terraform configuration helper function (e.g. `completePreflightPlan(data acceptance.TestData)`) that explicitly enables the `enhanced_validation.preflight_enabled` feature block and defines a complete, valid resource configuration.

### Example Test Structure

```go
func TestAccMyResource_completePreflightPlan(t *testing.T) {
	data := acceptance.BuildTestData(t, "azurerm_my_resource", "test")
	r := MyResource{}
	data.ResourceTest(t, r, []acceptance.TestStep{
		{
			Config:             r.completePreflightPlan(data),
			PlanOnly:           true,
			ExpectNonEmptyPlan: true,
		},
	})
}

func (r MyResource) completePreflightPlan(data acceptance.TestData) string {
	return fmt.Sprintf(`
provider "azurerm" {
  features {
    enhanced_validation {
      preflight_enabled = true
    }
  }
}

resource "azurerm_resource_group" "test" {
  name     = "acctestRG-myresource-%%[1]d"
  location = "%%[2]s"
}

resource "azurerm_my_resource" "test" {
  name                = "acctest-myres-%%[1]d"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location
  // ... other required properties
}
`, data.RandomInteger, data.Locations.Primary)
}
```

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
