---
name: resource-framework-migration
description: Assist in migrating resources from `terraform-plugin-sdk` (legacy) to `terraform-plugin-framework` using the `internal/sdk` wrapper.
triggers:
  - "migrate resource to terraform-plugin-framework"
  - "convert resource to framework"
  - "refactor legacy resource"
  - "internal/sdk wrapper"
---

# Resource Migration Skill

This skill assists in migrating existing Terraform resources from the `terraform-plugin-sdk` (v2) to the `terraform-plugin-framework` using the custom wrapper located in `internal/sdk`.

## Overview

The `internal/sdk` wrapper provides a bridge between the legacy `ResourceData` patterns and the framework's typed models. It simplifies the migration by handling boilerplate and providing familiar (yet type-safe) methods.

## Migration Steps

### 1. Define the Resource Model

All resource models must be placed in a file named `*_models.go` within the service directory (e.g., `linux_virtual_machine_models.go`).

#### Naming Conventions
- **Main Model**: `[resourceName]ResourceModel` (e.g., `linuxVirtualMachineResourceModel`).
- **Nested Models**: `[resourceName][Property]Model` (e.g., `virtualMachineSSHKeyModel`).

#### Field Types
- **Primitives**: Always use the `types` package (e.g., `types.String`, `types.Bool`, `types.Int64`).
- **Lists/Sets of Primitives**: Use `types.List` or `types.Set`.
- **Nested Objects**: Use `typehelpers.ListNestedObjectValueOf[T]` or `typehelpers.SetNestedObjectValueOf[T]`.
- **Maps**: Use `typehelpers.MapValueOf[types.String]`.

#### Struct Tags
Struct tags must match the schema property names **exactly**.

```go
type exampleResourceModel struct {
	ID        types.String                         `tfsdk:"id"`
	Name      types.String                         `tfsdk:"name"`
	Location  types.String                         `tfsdk:"location"`
	Tags      typehelpers.MapValueOf[types.String] `tfsdk:"tags"`
	Secret    typehelpers.ListNestedObjectValueOf[exampleSecretModel] `tfsdk:"secret"`
}
```

### 2. Implement `sdk.FrameworkWrappedResource`

Your resource struct must implement the `sdk.FrameworkWrappedResource` interface.

```go
type exampleResource struct{}

func (r *exampleResource) ResourceType() string {
	return "azurerm_example_resource"
}

func (r *exampleResource) ModelObject() any {
	return &exampleResourceModel{}
}
```

### 3. Migrate the Schema

Implement the `Schema` method. Map `pluginsdk.Schema` to framework `schema.Attribute`.

- `TypeString` -> `schema.StringAttribute`
- `TypeBool` -> `schema.BoolAttribute`
- `TypeInt` -> `schema.Int64Attribute`
- `TypeFloat` -> `schema.Float64Attribute`
- `TypeList`/`TypeSet` -> `schema.ListAttribute`/`schema.SetAttribute` (or `ListNestedBlock`/`SetNestedBlock`)

### 4. Implement CRUD Operations

The wrapper provides `Create`, `Read`, `Update`, and `Delete` methods that take `sdk.ResourceMetadata` and the decoded model.

```go
func (r *exampleResource) Create(ctx context.Context, req resource.CreateRequest, resp resource.CreateResponse, meta sdk.ResourceMetadata, plan any) {
    data := plan.(*exampleResourceModel)
    // ... expansion logic (similar to legacy, but using data fields directly)
}
```

### 5. Advanced Logic (Plan Modification & Validation)

If the resource requires plan modification (e.g., `RequiresReplace`) or complex validation, implement:
- `sdk.FrameworkWrappedResourceWithPlanModifier` (`ModifyPlan` method)
- `sdk.FrameworkWrappedResourceWithConfigValidators` (`ConfigValidators` method)

### 6. Resource Registration

In `internal/services/<service>/registration.go`, add the resource to the `resources` slice:

```go
func (r Registration) FrameworkResources() []sdk.FrameworkWrappedResource {
	if !features.FivePointOh() {
		return []sdk.FrameworkWrappedResource{}
	}

	return []sdk.FrameworkWrappedResource{
		&exampleResource{},
	}
}
```

## Common Utilities

The framework implementation relies on several utility packages within the provider and `go-azure-helpers`:

- **`fwcommonschema`**: Common attributes like `Name`, `ResourceGroupName`, `Location`, and `Tags`.
- **`typehelpers`**: Helpers for working with framework types, such as `WrappedStringValidator` and `NewWrappedStringDefault`.
- **`values`**: Utilities for converting between framework types and Go types (e.g., `ValueStringPointer`).
- **`pointer`**: (from `go-azure-helpers`) Standard pointer utilities.

## Comparison Patterns

| Feature | Plugin SDK (Legacy) | Framework Wrapper |
|---------|---------------------|-------------------|
| Data Access | `d.Get("name").(string)` | `data.Name.ValueString()` |
| Errors | `return fmt.Errorf(...)` | `sdk.SetResponseErrorDiagnostic(resp, ...)` |
| Identity | `d.SetId(id.ID())` | `data.ID = types.StringValue(id.ID())` |
| Defaults | `Default: "value"` | `Default: typehelpers.NewWrappedStringDefault("value")` |
| Expanders | `expandFoo(d.Get("foo").([]interface{}))` | `expandFooModel(ctx, data.Foo, &resp.Diagnostics)` |

## Best Practices

1. **Avoid `d.Get`**: Use the typed model fields directly.
2. **Use `sdk.AssertResourceModelType`**: Always assert your model type at the start of CRUD methods.
3. **Handle Transitions**: Be careful with `RequiresReplace` vs. `RequiresReplaceIfConfigured`.
4. **Validation**: Prefer framework validators (e.g., `stringvalidator`) over legacy `ValidateFunc` where possible, or wrap them using `typehelpers.WrappedStringValidator`.

## Safety & Verification

- **Human Review**: All AI-generated code must be manually verified.
- **No Bot PRs**: Skills should assist humans, not automate the PR submission itself.
- **State Awareness**: The AI cannot see the real Azure environment; it must rely on the user to provide `terraform plan` output for validation.
- **Functional Parity**: The Framework implementation should maintain parity with the legacy implementation unless a breaking change is explicitly intended.

## Reference

- [linux_virtual_machine_framework_resource.go](file:///Users/ste/code/go/src/github.com/hashicorp/terraform-provider-azurerm/internal/services/compute/linux_virtual_machine_framework_resource.go)
- `internal/sdk/README.md`
