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

Use `features.FivePointOh()` to maintain legacy behavior for the current major version. The focus is on making it as easy as possible to remove the unused code path. The default code path should be the new major version, and the legacy code path and schema modification to legacy should be gated behind a `!features.FivePointOh()` check so the future work to remove the legacy code path is minimal.

> **Note:** Do not use in-lined anonymous functions in a property's schema definition to conditionally change the default value, validation function, etc. These will no longer be accepted in the provider. Regardless of the number of arguments changing, update the whole schema definition block rather than making inline changes.

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

If you are changing a default value, update the default value in the main schema definition and patch over it with the old default using `!features.FivePointOh()`:

```go
"spark_version": {
    Type:     pluginsdk.TypeString,
    Optional: true,
    Default: "3.4",
},
// ...
if !features.FivePointOh() {
    args["spark_version"].Default = "2.4"
}
```

### 2. Update CRUD Functions

Handle both properties in your logic. **It is critical that you strictly follow the `if !features.FivePointOh() { ... } else { ... }` pattern.** This ensures that the post-major release cleanup is as low effort as possible—consisting mostly of deleting the `if` block and keeping the `else` block.

To achieve this, duplicate the future 5.0 logic inside the legacy `if` branch if necessary (e.g., when checking if the user supplied the new property early). The `else` block must contain **only** the pure, final 5.0 code without any legacy conditionals. 

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

### 4. Tests

- Update test configurations to use the new property, but keep one test using the old property.
- Switch the test between old and new properties conditionally using the `features.FivePointOh()` feature flag.
- Wherever possible, only update the test configuration and avoid updating the test case since changes to the test cases are more involved and higher effort to clean up.

### 5. Documentation and Upgrade Guide

- **Upgrade Guide**: Update the upgrade guide (`website/docs/5.0-upgrade-guide.markdown`). Add an entry under `## Breaking changes in Resources` (or Data Sources) in alphabetical order, detailing the removed property, the new property, or the new default values.
- **Resource Documentation**: Remove the deprecated property from the resource documentation and add the new property.
  - **Important**: Breaking changes such as the default value changing, or other property behaviour changing in a way that will only be active when the major release has gone out *should not* be added to the documentation since these do not apply yet. Do not add any `**Note:** This property will do x in 5.0` notes in the documentation.

## Safety & Verification

- **ConflictsWith**: Always set `ConflictsWith` between old and new properties to prevent ambiguity.
- **Reference**: Follow the [Breaking Changes Guide](file:///Users/ste/code/go/src/github.com/hashicorp/terraform-provider-azurerm/contributing/topics/guide-breaking-changes.md).

## Formatting

When you modify a file that contains Terraform configuration (e.g., acceptance tests, markdown documentation), you **MUST** run the `terrafmt fmt -f <file>` command on the file to ensure the configuration meets Terraform's formatting standards.
