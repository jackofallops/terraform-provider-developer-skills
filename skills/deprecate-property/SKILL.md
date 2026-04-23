---
name: deprecate-property
description: Assist in deprecating or renaming a property, following the breaking changes guide.
triggers:
  - "deprecate property"
  - "rename property"
  - "change default value"
---

# Deprecate Property Skill

This skill assists in deprecating, renaming, or changing the behavior of a property in a way that will be finalized in the next major version (v5.0).

## Steps to Deprecate/Rename a Property

### 1. Update the Schema

Use `features.FivePointOh()` to maintain legacy behavior for the current major version. The focus is on making it as easy as possible to remove the unused code path as easily as possible. The default code path should be the new major version, and the legacy code path and schema modification to legacy should be gated behind a `!features.FivePointOh()` check so the future work to remove the legacy code path is minimal.

```go
"new_property": {
    Type:     pluginsdk.TypeString,
    Optional: true,
},
// ...
if !features.FivePointOh() {
    args["old_property"] = &pluginsdk.Schema{
        Type:          pluginsdk.TypeString,
        Optional:      true,
        Computed:      true, // Set both to Computed for renames
        ConflictsWith: []string{"new_property"},
        Deprecated:    "`old_property` has been deprecated in favour of `new_property` and will be removed in v5.0 of the AzureRM Provider",
    }
    args["new_property"].Computed = true
    args["new_property"].ConflictsWith = []string{"old_property"}
}
```

### 2. Update CRUD Functions

Handle both properties in your logic. To make the post 5.0 code as easy as possible to remove, **always** structure your flow using `if !features.FivePointOh() { ... } else { ... }`. 
Duplicate the future 5.0 logic inside the legacy branch if necessary (e.g. when checking if the user supplied the new property early), so that the `else` block contains the pure, final 5.0 code without any legacy conditionals. 

```go
if !features.FivePointOh() {
    // 1. Check if they used the new property (optional in 4.x)
    if v, ok := d.GetOk("new_property"); ok && v.(string) != "" {
        // Run 5.0 behavior manually for 4.x users adopting early
    } else {
        // Run legacy 4.x behavior
    }
} else {
    // Pure 5.0 behavior. The new property is required here.
    // This block will cleanly become the main block when 5.x ships.
}
```

### 3. Handle Typed Models (v5.0 readiness)

For Typed resources, ensure the old field in the model struct is tagged for removal.

```go
type ExampleModel struct {
    OldProperty string `tfschema:"old_property,removedInNextMajorVersion"`
    NewProperty string `tfschema:"new_property"`
}
```

### 4. Tests and Docs

- Update test configurations to use the new property, but keep one test using the old property (switched via feature flag).
- Update the upgrade guide (`website/docs/5.0-upgrade-guide.markdown`).
- Remove the deprecated property from the main documentation.

## Safety & Verification

- **ConflictsWith**: Always set `ConflictsWith` between old and new properties to prevent ambiguity.
- **Reference**: Follow the [Breaking Changes Guide](file:///Users/ste/code/go/src/github.com/hashicorp/terraform-provider-azurerm/contributing/topics/guide-breaking-changes.md).
