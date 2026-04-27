---
name: migrate-to-typed-resource
description: Assist in converting a native (*pluginsdk.Resource) resource to the Typed SDK wrapper (internal/sdk), following the provider's current implementation standard.
triggers:
  - "migrate native resource to typed"
  - "convert pluginsdk resource to sdk.Resource"
  - "modernise legacy resource"
  - "native to typed"
  - "migrate-to-typed-resource"
---

# Migrate Native Resource to Typed

This skill converts a legacy native resource (`func resourceExample() *pluginsdk.Resource`)
to the Typed SDK wrapper (`type ExampleResource struct{}` implementing `sdk.Resource`).

The migration is mechanical but has several well-known gotchas. Follow every step in order.

---

## Anatomy comparison

| Concern | Native | Typed |
|---|---|---|
| Resource definition | `func resourceExample() *pluginsdk.Resource` | `type ExampleResource struct{}` |
| Schema | Single `Schema map[string]*pluginsdk.Schema` | `Arguments()` + `Attributes()` methods |
| Model | None — `d.Get("field").(string)` | `type ExampleResourceModel struct { Field string \`tfschema:"field"\` }` |
| CRUD signature | `func(d *pluginsdk.ResourceData, meta interface{})` | `sdk.ResourceFunc{ Timeout, Func: func(ctx, metadata) }` |
| Client access | `meta.(*clients.Client).X` | `metadata.Client.X` |
| State read | `d.Get("field").(string)` | `metadata.Decode(&model)` then `model.Field` |
| State write | `d.Set("field", value)` | set model field, `metadata.Encode(&state)` |
| ID set | `d.SetId(id.ID())` | `metadata.ResourceData.SetId(id.ID())` |
| ID read | `d.Id()` | `metadata.ResourceData.Id()` |
| Import | `Importer: pluginsdk.ImporterValidatingResourceId(...)` | `IDValidationFunc()` (automatic) |
| Timeouts | `Timeouts: &pluginsdk.ResourceTimeout{...}` | `ResourceFunc.Timeout` per method |
| Update optional | `Update:` field; omit if all fields are `ForceNew` | implement `sdk.ResourceWithUpdate` interface |
| CustomizeDiff | `CustomizeDiff:` field | implement `sdk.ResourceWithCustomizeDiff` interface |
| State migration | `SchemaVersion` + `StateUpgraders` slice | implement `sdk.ResourceWithStateMigration` interface |
| Registration | `SupportedResources() map[string]*pluginsdk.Resource` | `Resources() []sdk.Resource` |
| Logging | `log.Printf("[DEBUG] ...")` | `metadata.Logger.Infof(...)` |

---

## Step 0 — Pre-migration audit

Before writing any code, collect the following facts about the target resource. These
determine which optional steps apply:

| Question | Impact |
|---|---|
| Does it have `StateUpgraders`? | Must implement `sdk.ResourceWithStateMigration`; schema version must be preserved |
| Does it have `SchemaVersion > 0`? | State migration required regardless of upgrader count |
| Does it have `CustomizeDiff`? | Must implement `sdk.ResourceWithCustomizeDiff` |
| Does the `Update` func exist? | Must implement `sdk.ResourceWithUpdate` |
| Does the `Importer` use a custom function? | May need `sdk.ResourceWithCustomImporter` |
| Does it use `parse/` package IDs? | Must verify ID format matches typed ID or state migration needed |
| Does any field use `d.Set()` with complex nested maps? | Requires careful model struct design |
| Does it use `timeouts.For*` calls? | Replace with `ResourceFunc.Timeout` |
| Does it use global `locks.ByName`? | Locks are unchanged — carry over as-is |

> [!IMPORTANT]
> **If `SchemaVersion` is non-zero or `StateUpgraders` are present**, the typed resource
> MUST preserve the same `SchemaVersion` and implement `sdk.ResourceWithStateMigration`.
> Resetting to version 0 will corrupt existing user state. Refer to the
> `state-upgrade-required` skill for upgrader implementation details.

### Rename the source file

Before writing any new code, rename the existing `example_resource.go` to
`example_resource_legacy.go`. This prevents filename collisions when the new typed
`example_resource.go` is created and avoids confusion about which file is canonical during
the migration.

Once the migration is complete and all legacy CRUD functions have been removed, delete
`example_resource_legacy.go` entirely. Do not leave it in the repository.

---

## Step 1 — Create the model struct

Create the new `example_resource.go`. For large resources, a companion
`example_resource_models.go` is acceptable.

**Rules:**
- Struct name: `ExampleResourceModel`
- Field names: PascalCase
- Tags: `tfschema:"schema_key_name"` — must match schema keys **exactly**
- Nested blocks: separate `type ExampleNestedModel struct` with `tfschema:` tags
- Primitive types: `string`, `bool`, `int64`, `float64` — not pointer types
- Lists/sets of primitives: `[]string`, `[]int64`
- Lists/sets of nested objects: `[]NestedModel`
- Computed-only fields: included in model with `tfschema:` tags; populated only in `Read()`

**Example translation:**

```go
// Native schema
"admin_email": { Type: pluginsdk.TypeString, Required: true },
"tags":        { Type: pluginsdk.TypeMap, Optional: true },
"admin": {
    Type: pluginsdk.TypeList, Optional: true,
    Elem: &pluginsdk.Resource{Schema: map[string]*pluginsdk.Schema{
        "name": {Type: pluginsdk.TypeString, Required: true},
    }},
},

// Typed model
type ExampleResourceModel struct {
    AdminEmail string            `tfschema:"admin_email"`
    Tags       map[string]string `tfschema:"tags"`
    Admin      []AdminModel      `tfschema:"admin"`
}

type AdminModel struct {
    Name string `tfschema:"name"`
}
```

---

## Step 2 — Translate the schema

Split the single `Schema` map into two methods:

- **`Arguments()`**: All `Required` and `Optional` fields (user-configurable)
- **`Attributes()`**: `Computed`-only fields (read-only from the API)
- Fields that are `Optional+Computed` go into `Arguments()`, not `Attributes()`

Schema key names and all field properties (`ForceNew`, `ValidateFunc`, `AtLeastOneOf`,
etc.) are carried over unchanged.

---

## Step 3 — Implement required interface methods

```go
type ExampleResource struct{}

var _ sdk.Resource = ExampleResource{}

func (r ExampleResource) ResourceType() string {
    return "azurerm_example" // must be identical to the SupportedResources() map key
}

func (r ExampleResource) ModelObject() interface{} {
    return &ExampleResourceModel{}
}

func (r ExampleResource) IDValidationFunc() pluginsdk.SchemaValidateFunc {
    return mypackage.ValidateExampleID // replaces the Importer validation func
}
```

**Import handling:**

| Native pattern | Typed equivalent |
|---|---|
| `pluginsdk.ImporterValidatingResourceId(validateFunc)` | `IDValidationFunc()` returning that validate func — import is automatic |
| `pluginsdk.ImporterValidatingResourceIdThen(validateFunc, customFunc)` | `sdk.ResourceWithCustomImporter` — `CustomImporter()` returns the custom logic |

---

## Step 4 — Translate CRUD functions

Each CRUD function becomes an `sdk.ResourceFunc`. The `Timeout` field replaces the native
`Timeouts` block for that operation.

**Pattern:**

```go
func (r ExampleResource) Create() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Timeout: 30 * time.Minute,
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            client := metadata.Client.Example.ExampleClient

            var model ExampleResourceModel
            if err := metadata.Decode(&model); err != nil {
                return err
            }

            // ... resource logic using model fields directly ...

            metadata.ResourceData.SetId(id.ID())
            return nil
        },
    }
}
```

**Translation reference:**

| Native | Typed |
|---|---|
| `meta.(*clients.Client).X` | `metadata.Client.X` |
| `d.Get("field").(string)` | `model.Field` (after `Decode`) |
| `d.Set("field", value)` | `state.Field = value` (before `Encode`) |
| `d.SetId(id)` | `metadata.ResourceData.SetId(id)` |
| `d.Id()` | `metadata.ResourceData.Id()` |
| `d.HasChange("field")` | `metadata.ResourceData.HasChange("field")` |
| `timeouts.ForCreate(ctx, d)` | `ctx` already carries the `ResourceFunc.Timeout` |
| `utils.ResponseWasNotFound(resp)` | `response.WasNotFound(resp.HttpResponse)` (go-azure-helpers) |
| `log.Printf("[DEBUG] ...")` | `metadata.Logger.Infof(...)` |
| `tf.ImportAsExistsError(...)` | `metadata.ResourceRequiresImport(r.ResourceType(), id)` |

**`Read()` state-not-found pattern:**

```go
// Native
if utils.ResponseWasNotFound(resp.Response) {
    log.Printf("[DEBUG] %s was not found - removing from state!", id)
    d.SetId("")
    return nil
}

// Typed
if response.WasNotFound(resp.HttpResponse) {
    return metadata.MarkAsGone(id)
}
```

---

## Step 5 — Optional interfaces

Implement only the interfaces identified in the Step 0 audit.

**Update:**

```go
var _ sdk.ResourceWithUpdate = ExampleResource{}

func (r ExampleResource) Update() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Timeout: 30 * time.Minute,
        Func:    func(ctx context.Context, metadata sdk.ResourceMetaData) error { ... },
    }
}
```

**CustomizeDiff:** See the `modify-typed-resource` skill for the full interface and skeleton.

**State migration:**

```go
var _ sdk.ResourceWithStateMigration = ExampleResource{}

func (r ExampleResource) StateUpgraders() sdk.StateUpgradeData {
    return sdk.StateUpgradeData{
        SchemaVersion: 2, // MUST match the original native SchemaVersion exactly
        Upgraders: map[int]pluginsdk.StateUpgrade{
            0: migration.ExampleV0ToV1{},
            1: migration.ExampleV1ToV2{},
        },
    }
}
```

See the `state-upgrade-required` skill for upgrader implementation details.

---

## Step 6 — Update registration

This step wires the new typed resource into the provider. **Until this step is complete the
new resource struct is compiled but never exercised.**

### 6a — Add to `Resources()`

```go
func (r Registration) Resources() []sdk.Resource {
    return []sdk.Resource{
        ExampleResource{},
    }
}
```

If `Resources()` does not exist yet, add it. Check the existing interface assertions at the
top of `registration.go` — the registration may already implement one of the
`TypedServiceRegistration` interfaces (any of `sdk.TypedServiceRegistration`,
`sdk.TypedServiceRegistrationWithAGitHubLabel`, etc., all expose `Resources()`). If none
are present, add the appropriate one alongside the existing untyped assertion:

```go
var (
    _ sdk.UntypedServiceRegistrationWithAGitHubLabel = Registration{} // existing example
    _ sdk.TypedServiceRegistrationWithAGitHubLabel   = Registration{} // add if absent
)
```

### 6b — Remove from `SupportedResources()`

```go
func (r Registration) SupportedResources() map[string]*pluginsdk.Resource {
    return map[string]*pluginsdk.Resource{
        // DELETE: "azurerm_example": resourceExample(),
    }
}
```

If `SupportedResources()` becomes empty, leave it returning an empty map — do not remove
the method, as the interface requires it.

### 6c — Verify

```bash
grep 'ExampleResource{}' internal/services/<service>/registration.go
```

---

## Step 7 — Remove the legacy file

Delete `example_resource_legacy.go` and its contained CRUD functions. Keep any
helper/expand/flatten functions that are still called by the typed implementation.

---

## Key gotchas

> [!WARNING]
> **ID format must be identical.** If the native resource uses a hand-crafted `parse/`
> package ID and the typed resource uses a `go-azure-sdk` typed ID, verify both produce
> identical string output for the same resource. If they differ at all (capitalisation,
> path segment order), a state migration is **mandatory**.

> [!WARNING]
> **`SchemaVersion` must be preserved.** The typed SDK wrapper defaults to version 0.
> If the native resource has `SchemaVersion: 1`, the typed resource must declare the same
> version via `sdk.ResourceWithStateMigration` — otherwise existing user state is corrupted.

> [!NOTE]
> **`d.HasChange` still works.** `metadata.ResourceData.HasChange("field")` is valid in
> typed resources and is the correct pattern in `Update()`.

> [!NOTE]
> **`parse/` IDs are valid in typed resources.** Do not switch to a `go-azure-sdk` typed ID
> unless verified to produce an identical string — an ID format change requires a state
> migration and is out of scope for a pure style migration.

---

## Verification

1. `go vet ./...` from the repo root — zero diagnostics in the service package
2. `go test ./internal/services/<service>/...` — all non-acceptance tests pass
   (`TF_ACC=1` must **not** be set; acceptance tests will skip automatically without it)
3. Confirm `SchemaVersion` in typed resource matches original native `SchemaVersion`
4. Confirm `ResourceType()` string is identical to the map key removed from `SupportedResources()`
5. Human review of ID format: parse the same ID string with both the old `parse/` function
   and the new typed ID parser and confirm identical output
