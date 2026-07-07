---
name: deprecate-property
description: Assist in deprecating or renaming a property, following the provider's breaking changes guide.
triggers:
  - "deprecate property"
  - "rename property"
  - "change default value"
---

# Deprecate Property Skill

This skill assists in deprecating, renaming, or changing the behavior of a property in a way that will be finalized in the next major version.

## Steps to Deprecate/Rename a Property

### 1. Update the Schema

First, check the `version/VERSION` file to determine the current major version. Then, use the feature flag for the *next* major version from the `features` package (e.g., if the current version is 4.x, use `features.FivePointOh()`) to maintain legacy behavior for the current major version. The focus is on making it as easy as possible to remove the unused code path. The default code path should be the new major version, and the legacy code path and schema modification to legacy should be gated behind a `!features.FivePointOh()` check so the future work to remove the legacy code path is minimal.

> **Note:** Do not use in-lined anonymous functions in a property's schema definition to conditionally change the default value, validation function, etc. Regardless of the number of arguments changing, update the whole schema definition block rather than making inline changes.

```go
"new_property": {
    Type:     pluginsdk.TypeString,
    Optional: true,
},
// ...
// Ensure you REMOVE `old_property` entirely from the main schema map above!
if !features.FivePointOh() {
    args["old_property"] = &pluginsdk.Schema{
        Type:          pluginsdk.TypeString,
        Optional:      true,
        Computed:      true, // Set both to Computed for renames
        ConflictsWith: []string{"new_property"}, // ConflictsWith can only be used for top-level or nested arguments in a list with MaxItems = 1
        Deprecated:    "`old_property` has been deprecated in favour of `new_property` and will be removed in the next major version of the Provider",
    }
    args["new_property"].&pluginsdk.Schema{
        Type:          pluginsdk.TypeString,
        Optional:      true,
        Computed:      true,
        ConflictsWith: []string{"old_property"},
    }
}
```

If you are changing a default value, update the default value in the main schema definition and patch over it with the old default using the feature flag:

```go
"spark_version": {
    Type:     pluginsdk.TypeString,
    Optional: true,
    Default: "3.4",
},
// ...
if !features.FivePointOh() {
    args["spark_version"] = &pluginsdk.Schema{
        Type:     pluginsdk.TypeString,
        Optional: true,
        Default: "2.4", // Old default value
    }
}
```

### 2. Update CRUD Functions

Handle both properties in your logic. **It is critical that you strictly follow one of the options below:**

1. `... <major release logic> ... if !features.NextMajorVersion() { ... }` - use this pattern when possible
2. `if !features.NextMajorVersion() { ... } else { ... }` - use this pattern when the change is complex

This ensures that the post-major release cleanup is as low effort as possible, consisting mostly of deleting the `if` block (and keeping the `else` block in case of option 2).

Option 1:
```go
// Pure future behavior. The new property must be used here.
// This is active by default, ensuring the new property can be used immediately.

if !features.NextMajorVersion() {
    // Check if they used the old property instead of the new, if so, run the legacy behavior
	// Note: because both properties are Optional + Computed, a `GetOk` check will not work, we must access RawConfig to determine if it was set
    if !pluginsdk.IsExplicitlyNullInConfig(d, "old_property") { // Note: the `IsExplicitlyNullInConfig` helper only works with top level arguments
        // Run legacy behavior
    }
}
```

Option 2:
```go
if !features.FivePointOh() {
    // 1. Check if they used the new property (optional in current major version)
    // Note: because both properties are Optional + Computed, a `GetOk` check will not work, we must access RawConfig to determine if it was set
    if !pluginsdk.IsExplicitlyNullInConfig(d, "new_property") { // Note: the `IsExplicitlyNullInConfig` helper only works with top level arguments
        // Run future behavior manually for users adopting early
    } else {
        // Run legacy behavior
    }
} else {
    // Pure future behavior. The new property is required here.
    // This block will cleanly become the main block when the new major version ships.
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

- **Upgrade Guide**: Update the provider's upgrade guide (e.g., `website/docs/<next_major_version>-upgrade-guide.html.markdown`). Add an entry under `## Breaking changes in Resources` (or Data Sources) in alphabetical order, detailing the removed property, the new property, or the new default values.
- **Resource Documentation**: Remove the deprecated property from the resource documentation and add the new property.
  - **Important**: Breaking changes such as the default value changing, or other property behaviour changing in a way that will only be active when the major release has gone out *should not* be added to the documentation since these do not apply yet. Do not add any `**Note:** This property will do x in vNext` notes in the documentation.

## Safety & Verification

- **ConflictsWith**: Always set `ConflictsWith` between old and new properties to prevent ambiguity.
- **Reference**: Follow the provider's breaking changes guide (e.g., `terraform-provider-azurerm/contributing/topics/guide-breaking-changes.md` if working on AzureRM).

## Formatting

When you modify a file that contains Terraform configuration (e.g., acceptance tests, markdown documentation), you **MUST** run the `terrafmt fmt -f <file>` command on the file to ensure the configuration meets Terraform's formatting standards.
