---
name: modify-native-resource
description: Assist in adding a new property to an existing legacy resource (native Plugin SDK).
triggers:
  - "add property to native resource"
  - "modify legacy resource schema"
  - "pluginsdk resource modification"
---

# Modify Native Resource Skill

This skill assists in adding a new property to an existing legacy resource that uses the `terraform-plugin-sdk` (v2) directly.

## Identification

A native resource typically looks like this:

```go
func resourceExample() *pluginsdk.Resource {
    return &pluginsdk.Resource{
        Schema: map[string]*pluginsdk.Schema{
            // ...
        },
        Create: resourceExampleCreate,
        Read:   resourceExampleRead,
        // ...
    }
}
```

## Steps to Add a Property

### 1. Update the Schema

Find the `Schema` map and add the new property.

```go
"new_property": {
    Type:     pluginsdk.TypeString,
    Optional: true,
    // ForceNew: true, // If changing it requires recreation
},
```

### 2. Update Create Function

Retrieve the value from `ResourceData` and add it to the API client payload.

```go
func resourceExampleCreate(d *pluginsdk.ResourceData, meta interface{}) error {
    // ...
    if v, ok := d.GetOk("new_property"); ok {
        params.NewProperty = pointer.To(v.(string))
    }
    // ...
}
```

### 3. Update the Update Function

If the property is not `ForceNew`, it should be handled in the `Update` function. Check if the property has changed before sending it to the API.

```go
func resourceExampleUpdate(d *pluginsdk.ResourceData, meta interface{}) error {
    // ...
    if d.HasChange("new_property") {
        params.NewProperty = pointer.To(d.Get("new_property").(string))
    }
    // ...
}
```

### 4. Update the Read Function

Retrieve the value from the API response and set it back to `ResourceData`.

```go
func resourceExampleRead(d *pluginsdk.ResourceData, meta interface{}) error {
    // ...
    d.Set("new_property", response.NewProperty)
    // ...
}
```

## Adding CustomizeDiff

Native resources support a `CustomizeDiff` field in the `*pluginsdk.Resource` struct:

```go
func resourceExample() *pluginsdk.Resource {
    return &pluginsdk.Resource{
        // ... existing CRUD
        CustomizeDiff: pluginsdk.DefaultDiff(resourceExampleCustomizeDiff),
    }
}

func resourceExampleCustomizeDiff(ctx context.Context, d *pluginsdk.ResourceDiff, meta interface{}) error {
    // logic here
    return nil
}
```

-> **Note:** Preflight validation (`internal/preflight`) is not currently supported in
native resource `CustomizeDiff` functions without additional wiring. If preflight
validation is required, consider migrating the resource to the Typed SDK wrapper
using the `resource-framework-migration` skill.

## Safety & Verification

- **Human Review**: AI-generated schema changes must be verified for correct types and behaviors (e.g., `ForceNew`).
- **Functional Parity**: Ensure that adding the property doesn't break existing functionality.
- **State Awareness**: Rely on `terraform plan` to verify that the new property is recognized and behaves as expected.
