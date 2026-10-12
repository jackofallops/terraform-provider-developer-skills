---
name: add-list-resource
description: Assist in adding a new List Resource to an existing provider resource.
---

# `add-list-resource`

This skill provides step-by-step instructions for implementing a Terraform List Resource for an AzureRM resource, following [`contributing/topics/guide-list-resource.md`](../../contributing/topics/guide-list-resource.md).

A List Resource allows querying Azure resources via a Terraform `list` block (e.g. `list "azurerm_example" "list"`). Every new resource requires one, and CI checks for the `*_resource_list.go` file. If the Azure API does not support a list operation, note it in the PR so a maintainer can add the `list-not-supported` label.

---

## Prerequisites: Resource Identity

Before adding a List Resource, the underlying resource MUST implement Resource Identity. See [Guide: Resource Identity](../../contributing/topics/guide-resource-identity.md) or the `add-resource-identity` skill.

---

## Step 1: Refactor the Flatten Function

Refactor the resource's `Read` function to extract a standalone `flatten` function that sets attributes into state. This will be shared between `Read` and the List Resource.

### Untyped Resource (`*pluginsdk.Resource`)
```go
func resourceExampleFlatten(d *pluginsdk.ResourceData, id *example.ExampleId, item *example.ExampleModel) error {
    d.Set("name", id.ExampleName)
    d.Set("resource_group_name", id.ResourceGroupName)

    if item != nil {
        if props := item.Properties; props != nil {
            // Flatten and set properties into d
        }
        d.Set("location", location.NormalizeNilable(item.Location))
        if err := tags.FlattenAndSet(d, item.Tags); err != nil {
            return err
        }
    }
    return pluginsdk.SetResourceIdentityData(d, id)
}
```

### Typed Resource (`sdk.Resource`)
```go
func (ExampleResource) flatten(metadata sdk.ResourceMetaData, id *example.ExampleId, model *example.ExampleModel) error {
    state := ExampleResourceModel{
        Name:              id.ExampleName,
        ResourceGroupName: id.ResourceGroupName,
    }

    if model != nil {
        state.Location = location.Normalize(model.Location)
        if props := model.Properties; props != nil {
            // Flatten remaining properties into state
        }
    }

    if err := pluginsdk.SetResourceIdentityData(metadata.ResourceData, id); err != nil {
        return err
    }

    return metadata.Encode(&state)
}
```

---

## Step 2: Scaffold the List Resource File

Create `internal/services/<service>/<resource>_resource_list.go`.

### Untyped Resource
```go
type ExampleListResource struct{}

var _ sdk.FrameworkListWrappedResource = new(ExampleListResource)

func (ExampleListResource) ResourceFunc() *pluginsdk.Resource {
    return resourceExample()
}

func (r ExampleListResource) Metadata(_ context.Context, _ resource.MetadataRequest, response *resource.MetadataResponse) {
    response.TypeName = azureExampleResourceName
}
```

### Typed Resource
```go
type ExampleListResource struct{}

var _ sdk.FrameworkListWrappedResource = new(ExampleListResource)

func (ExampleListResource) ResourceFunc() *pluginsdk.Resource {
    return sdk.WrappedResource(ExampleResource{})
}

func (ExampleListResource) Metadata(_ context.Context, _ resource.MetadataRequest, response *resource.MetadataResponse) {
    response.TypeName = ExampleResource{}.ResourceType()
}
```

---

## Step 3: Define Custom List Configuration (Optional)

If using `sdk.DefaultListModel` (which supplies `subscription_id` and `resource_group_name`), this step is omitted.

If the resource requires custom filter parameters or is a sub-resource:
```go
type ExampleListModel struct {
    SubscriptionId    types.String `tfsdk:"subscription_id"`
    ResourceGroupName types.String `tfsdk:"resource_group_name"`
}

func (ExampleListResource) ListResourceConfigSchema(_ context.Context, _ list.ListResourceSchemaRequest, response *list.ListResourceSchemaResponse) {
    response.Schema = schema.Schema{
        Attributes: map[string]schema.Attribute{
            "subscription_id": schema.StringAttribute{
                Optional: true,
                Validators: []validator.String{
                    typehelpers.WrappedStringValidator{
                        Func: commonids.ValidateSubscriptionID,
                    },
                },
            },
            "resource_group_name": schema.StringAttribute{
                Optional: true,
                Validators: []validator.String{
                    typehelpers.WrappedStringValidator{
                        Func: resourcegroups.ValidateName,
                    },
                },
            },
        },
    }
}
```

---

## Step 4: Implement `List()`

### Untyped Resource
```go
func (ExampleListResource) List(ctx context.Context, request list.ListRequest, stream *list.ListResultsStream, metadata sdk.ResourceMetadata) {
    client := metadata.Client.Example.ExampleClient

    var data sdk.DefaultListModel
    diags := request.Config.Get(ctx, &data)
    if diags.HasError() {
        stream.Results = list.ListResultsStreamDiagnostics(diags)
        return
    }

    results := make([]example.ExampleModel, 0)

    subscriptionID := metadata.SubscriptionId
    if !data.SubscriptionId.IsNull() {
        subscriptionID = data.SubscriptionId.ValueString()
    }

    switch {
    case !data.ResourceGroupName.IsNull():
        resp, err := client.ListComplete(ctx, commonids.NewResourceGroupID(subscriptionID, data.ResourceGroupName.ValueString()))
        if err != nil {
            sdk.SetResponseErrorDiagnostic(stream, fmt.Sprintf("listing `%s`", azureExampleResourceName), err)
            return
        }
        results = resp.Items
    default:
        resp, err := client.ListAllComplete(ctx, commonids.NewSubscriptionID(subscriptionID))
        if err != nil {
            sdk.SetResponseErrorDiagnostic(stream, fmt.Sprintf("listing `%s`", azureExampleResourceName), err)
            return
        }
        results = resp.Items
    }

    stream.Results = func(push func(list.ListResult) bool) {
        for _, item := range results {
            result := request.NewListResult(ctx)
            result.DisplayName = pointer.From(item.Name)

            rd := resourceExample().Data(&terraform.InstanceState{})

            id, err := example.ParseExampleID(pointer.From(item.Id))
            if err != nil {
                sdk.SetErrorDiagnosticAndPushListResult(result, push, "parsing Example ID", err)
                return
            }
            rd.SetId(id.ID())

            if err := resourceExampleFlatten(rd, id, &item); err != nil {
                sdk.SetErrorDiagnosticAndPushListResult(result, push, fmt.Sprintf("encoding `%s` resource data", azureExampleResourceName), err)
                return
            }

            sdk.EncodeListResult(ctx, rd, &result)
            if result.Diagnostics.HasError() {
                push(result)
                return
            }

            if !push(result) {
                return
            }
        }
    }
}
```

### Typed Resource
```go
func (ExampleListResource) List(ctx context.Context, request list.ListRequest, stream *list.ListResultsStream, metadata sdk.ResourceMetadata) {
    client := metadata.Client.Example.ExampleClient

    var data sdk.DefaultListModel
    diags := request.Config.Get(ctx, &data)
    if diags.HasError() {
        stream.Results = list.ListResultsStreamDiagnostics(diags)
        return
    }

    var results []example.ExampleModel

    subscriptionID := metadata.SubscriptionId
    if !data.SubscriptionId.IsNull() {
        subscriptionID = data.SubscriptionId.ValueString()
    }

    r := ExampleResource{}

    switch {
    case !data.ResourceGroupName.IsNull():
        resp, err := client.ListByResourceGroupComplete(ctx, commonids.NewResourceGroupID(subscriptionID, data.ResourceGroupName.ValueString()))
        if err != nil {
            sdk.SetResponseErrorDiagnostic(stream, fmt.Sprintf("listing `%s`", r.ResourceType()), err)
            return
        }
        results = resp.Items
    default:
        resp, err := client.ListComplete(ctx, commonids.NewSubscriptionID(subscriptionID))
        if err != nil {
            sdk.SetResponseErrorDiagnostic(stream, fmt.Sprintf("listing `%s`", r.ResourceType()), err)
            return
        }
        results = resp.Items
    }

    stream.Results = func(push func(list.ListResult) bool) {
        for _, item := range results {
            result := request.NewListResult(ctx)
            result.DisplayName = pointer.From(item.Name)

            id, err := example.ParseExampleID(pointer.From(item.Id))
            if err != nil {
                sdk.SetErrorDiagnosticAndPushListResult(result, push, "parsing Example ID", err)
                return
            }

            rmd := sdk.NewResourceMetaData(metadata.Client, r)
            rmd.SetID(id)

            if err := r.flatten(rmd, id, &item); err != nil {
                sdk.SetErrorDiagnosticAndPushListResult(result, push, fmt.Sprintf("encoding `%s` resource data", r.ResourceType()), err)
                return
            }

            sdk.EncodeListResult(ctx, rmd.ResourceData, &result)
            if result.Diagnostics.HasError() {
                push(result)
                return
            }

            if !push(result) {
                return
            }
        }
    }
}
```

---

## Step 5: Register the List Resource

Open `internal/services/<service>/registration.go`. Add the struct to `ListResources()`:

```go
func (r Registration) ListResources() []sdk.FrameworkListWrappedResource {
    return []sdk.FrameworkListWrappedResource{
        ExampleListResource{},
    }
}
```

---

## Step 6: Write Acceptance Tests

Create `internal/services/<service>/<resource>_resource_list_test.go`:

```go
package example_test

import (
    "context"
    "fmt"
    "testing"

    "github.com/hashicorp/terraform-plugin-testing/helper/resource"
    "github.com/hashicorp/terraform-plugin-testing/querycheck"
    "github.com/hashicorp/terraform-plugin-testing/tfversion"
    "github.com/hashicorp/terraform-provider-azurerm/internal/acceptance"
    "github.com/hashicorp/terraform-provider-azurerm/internal/provider/framework"
)

func TestAccExample_list_basic(t *testing.T) {
    r := ExampleResource{}
    listResourceAddress := "azurerm_example.list"

    data := acceptance.BuildTestData(t, "azurerm_example", "test1")

    resource.Test(t, resource.TestCase{
        TerraformVersionChecks: []tfversion.TerraformVersionCheck{
            tfversion.SkipBelow(tfversion.Version1_14_0),
        },
        ProtoV5ProviderFactories: framework.ProtoV5ProviderFactoriesInit(context.Background(), "azurerm"),
        Steps: []resource.TestStep{
            {
                Config: r.basicList(data), // provision multiple resources (count = 3)
            },
            {
                Query:  true,
                Config: r.basicQuery(),
                QueryResultChecks: []querycheck.QueryResultCheck{
                    querycheck.ExpectLengthAtLeast(listResourceAddress, 3),
                },
            },
            {
                Query:  true,
                Config: r.basicQueryByResourceGroupName(),
                QueryResultChecks: []querycheck.QueryResultCheck{
                    querycheck.ExpectLength(listResourceAddress, 3),
                },
            },
        },
    })
}
```

---

## Step 7: Add Documentation

Create `./website/docs/list-resources/<resource>.html.markdown`:

````markdown
---
subcategory: "Example"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_example"
description: |-
  Lists Example resources.
---

# List resource: azurerm_example

Lists Example resources.

## Example Usage

### List all Examples in the subscription

```hcl
list "azurerm_example" "example" {
  provider = azurerm
  config {}
}
```

### List all Examples in a specific resource group

```hcl
list "azurerm_example" "example" {
  provider = azurerm
  config {
    resource_group_name = "example-rg"
  }
}
```

## Argument Reference

This list resource supports the following arguments:

* `resource_group_name` - (Optional) The name of the resource group to query.

* `subscription_id` - (Optional) The Subscription ID to query. Defaults to the value specified in the Provider Configuration.
````

---

## Special Considerations

### Sub-Resources
For sub-resources that can only be listed beneath a parent:
- Do not expose `subscription_id` or `resource_group_name`.
- Accept the immediate parent resource ID as a required argument in the custom config schema.
- Parse the parent ID and call the parent-specific list API.
- See `internal/services/mysql/mysql_flexible_database_resource_list.go` for reference.

### Cancelled Context in Stream Iterator
If additional API requests must be performed within `flatten` during streaming (`stream.Results`), the input `ctx` will already be done/cancelled when Terraform runs the stream. Recover the context using its deadline:

```go
deadline, ok := ctx.Deadline()
if !ok {
    sdk.SetResponseErrorDiagnostic(stream, "internal-error", "context had no deadline")
    return
}

stream.Results = func(push func(list.ListResult) bool) {
    ctx, cancel := context.WithDeadline(context.Background(), deadline)
    defer cancel()

    for _, item := range results {
        // use renewed ctx here
    }
}
```
