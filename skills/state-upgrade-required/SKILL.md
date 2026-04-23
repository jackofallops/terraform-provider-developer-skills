---
name: state-upgrade-required
description: Assist in creating a resource state migration for updating the schema and its values in a Terraform resource that uses terraform-plugin-sdk v2.
triggers:
  - "state upgrade"
  - "state migration"
  - "schema version upgrade"
---

# State Upgrade Required Skill

This skill assists in writing resource state migrations (upgrades) to safely migrate users from an older version of a resource schema to a newer version without requiring recreation of resources.

## Steps to Implement a State Upgrade

### 1. Create the Migration Function

State migrations are located in `internal/services/<service>/migration/`. You should create a new file named `<resource_name>_v<X>_to_v<Y>.go`.

This file must define a struct that implements the `pluginsdk.StateUpgrade` interface:

```go
package migration

import (
	"context"

	"github.com/hashicorp/terraform-provider-azurerm/internal/tf/pluginsdk"
)

var _ pluginsdk.StateUpgrade = ExampleResourceV0ToV1{}

type ExampleResourceV0ToV1 struct{}

// Schema returns the exact schema representation from the PREVIOUS version (V0)
func (ExampleResourceV0ToV1) Schema() map[string]*pluginsdk.Schema {
	return map[string]*pluginsdk.Schema{
		// ... Include the full previous schema here
	}
}

// UpgradeFunc performs the migration from the V0 raw state to the V1 raw state
func (ExampleResourceV0ToV1) UpgradeFunc() pluginsdk.StateUpgraderFunc {
	return func(ctx context.Context, rawState map[string]interface{}, meta interface{}) (map[string]interface{}, error) {
		// Example: Migrating a string property to an int
		// oldProp := rawState["old_property"].(string)
		// rawState["new_property"] = convertToInt(oldProp)
		// delete(rawState, "old_property")
		
		return rawState, nil
	}
}
```

### 2. Update the Resource Definition

The way you wire the state upgrade depends on whether the resource is `Typed` or `Untyped`.

#### For Typed Resources (using internal/sdk wrapper)

Typed resources must implement the `sdk.ResourceWithStateMigration` interface.

1. Add the interface compliance check:
```go
var (
	_ sdk.ResourceWithUpdate         = ExampleResource{}
	_ sdk.ResourceWithStateMigration = ExampleResource{}
)
```

2. Implement the `StateUpgraders()` function to return `sdk.StateUpgradeData`:
```go
func (r ExampleResource) StateUpgraders() sdk.StateUpgradeData {
	return sdk.StateUpgradeData{
		SchemaVersion: 1, // The NEW schema version
		Upgraders: map[int]pluginsdk.StateUpgrade{
			0: migration.ExampleResourceV0ToV1{},
		},
	}
}
```

#### For Untyped Resources (using standard pluginsdk)

Untyped resources return a `*pluginsdk.Resource` directly. 

1. Update the `SchemaVersion` and `StateUpgraders` on the `pluginsdk.Resource` object:
```go
func resourceExampleResource() *pluginsdk.Resource {
	return &pluginsdk.Resource{
		// ... other CRUD operations
		
		SchemaVersion: 1, // The NEW schema version
		StateUpgraders: pluginsdk.StateUpgrades(map[int]pluginsdk.StateUpgrade{
			0: migration.ExampleResourceV0ToV1{},
		}),
        // ...
	}
}
```

### Important Considerations

* **Schema Accuracy**: The `Schema()` method in the migration struct must exactly reflect the old schema version, NOT the new one.
* **Cumulative Migrations**: If upgrading from V0 to V2, you must run through V0->V1 and then V1->V2. State migrations chain together sequentially, so do not alter existing migration files when adding a new schema version; instead, write a new one (e.g. `ExampleResourceV1ToV2`).
