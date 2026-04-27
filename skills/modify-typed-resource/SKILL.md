---
name: modify-typed-resource
description: Assist in adding a new property to an existing legacy resource (Typed SDK wrapper).
triggers:
  - "add property to typed resource"
  - "modify typed sdk resource"
  - "internal/sdk/resource.go modification"
---

# Modify Typed Resource Skill

This skill assists in adding a new property to an existing legacy resource that uses the "Typed" SDK wrapper (`internal/sdk/resource.go`).

## Identification

A typed resource implements the `sdk.Resource` interface and typically has a companion `*Model` struct.

```go
type ExampleResourceModel struct {
    // ...
}

type ExampleResource struct{}
```

## Steps to Add a Property

### 1. Update the Model Struct

Add the field to the model struct with the `tfschema` tag.

```go
type ExampleResourceModel struct {
    // ...
    NewProperty string `tfschema:"new_property"`
}
```

### 2. Update Arguments or Attributes

Add the field to either the `Arguments()` (if user-configurable) or `Attributes()` (if read-only) method.

```go
func (r ExampleResource) Arguments() map[string]*pluginsdk.Schema {
    return map[string]*pluginsdk.Schema{
        // ...
        "new_property": {
            Type:     pluginsdk.TypeString,
            Optional: true,
        },
    }
}
```

### 3. Update Create Function

Access the property directly from the model after decoding.

```go
func (r ExampleResource) Create() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            var model ExampleResourceModel
            if err := metadata.Decode(&model); err != nil {
                return err
            }
            // Use model.NewProperty
        },
    }
}
```

### 4. Update the Update Function

In the `Update()` method, check if the property has changed before including it in the update payload (especially for PATCH operations).

```go
func (r ExampleResource) Update() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            // ...
            if metadata.ResourceData.HasChange("new_property") {
                // include in patch/update payload
            }
        },
    }
}
```

### 5. Update the Read Function

Set the property in the state model before encoding.

```go
func (r ExampleResource) Read() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            // ...
            state.NewProperty = *apiResponse.NewProperty
            return metadata.Encode(&state)
        },
    }
}
```

## Adding CustomizeDiff

To implement `CustomizeDiff` on a Typed resource, the resource struct must implement the
`sdk.ResourceWithCustomizeDiff` interface. Add the compliance assertion and the method:

```go
// Compile-time assertion — add alongside other interface assertions at the top of the file
var _ sdk.ResourceWithCustomizeDiff = ExampleResource{}

func (r ExampleResource) CustomizeDiff() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Timeout: 5 * time.Minute,
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            if metadata.ResourceDiff == nil {
                return nil
            }

            var model ExampleResourceModel
            if err := metadata.DecodeDiff(&model); err != nil {
                return err
            }

            // logic here

            return nil
        },
    }
}
```

The SDK wrapper in `sdk/wrapper_resource.go` automatically detects the interface and wires
up `CustomizeDiff` — no changes to the resource registration function are needed.

## Safety & Verification

- **Human Review**: Verify that the `tfschema` tag matches the schema key.
- **Model Validation**: Ensure the model struct accurately reflects the API response.
- **State Awareness**: Use `terraform plan` to verify that the new property is correctly tracked in the state.
