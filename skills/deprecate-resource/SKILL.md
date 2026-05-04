---
name: deprecate-resource
description: Assist in deprecating an existing resource or data source, following the breaking changes guide.
triggers:
  - "deprecate resource"
  - "remove resource in 5.0"
  - "retire service"
---

# Deprecate Resource Skill

This skill assists in deprecating a resource or data source that will be removed in the next major version (v5.0).

## Steps to Deprecate a Resource

### 1. Add Deprecation Message

**For Native (Pluginsdk) Resources**:
Set the `DeprecationMessage` in the resource definition.
```go
DeprecationMessage: "The `azurerm_example` resource has been deprecated and will be removed in v5.0 of the AzureRM Provider"
```

**For Typed Resources**:
Implement `sdk.ResourceWithDeprecationAndNoReplacement` or `sdk.ResourceWithDeprecationReplacedBy`.
```go
func (r ExampleResource) DeprecationMessage() string {
    return "The `azurerm_example` resource has been deprecated and will be removed in v5.0 of the AzureRM Provider"
}
```

### 2. Conditional Registration

In the service's `registration.go`, wrap the resource registration with the major version feature flag.
```go
if !features.FivePointOh() {
    resources = append(resources, ExampleResource{})
}
```

### 3. Handle Tests

Conditionally skip tests in the test file.
```go
if features.FivePointOh() {
    t.Skipf("Skipping since `azurerm_example` is deprecated and will be removed in 5.0")
}
```
*Note: If the Azure API no longer works, remove the test file entirely.*

### 4. Documentation

- Add a `Note` to the resource documentation (`website/docs/r/*.html.markdown`).
- Update the upgrade guide (`website/docs/5.0-upgrade-guide.markdown`) under `## Removed Resources`.

## Safety & Verification

- **Feature Flag**: Always use `features.FivePointOh()` (or current major version flag) for conditional logic.
- **Reference**: Follow the [Breaking Changes Guide](file:///Users/ste/code/go/src/github.com/hashicorp/terraform-provider-azurerm/contributing/topics/guide-breaking-changes.md).

## Formatting

When you modify a file that contains Terraform configuration (e.g., acceptance tests, markdown documentation), you **MUST** run the `terrafmt fmt -f <file>` command on the file to ensure the configuration meets Terraform's formatting standards.
