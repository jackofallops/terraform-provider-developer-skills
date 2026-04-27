---
name: provider-docs
description: Create or update azurerm provider documentation. Covers all doc types in website/docs/ with correct structure, frontmatter, and formatting rules.
triggers:
  - "write documentation"
  - "update docs"
  - "add resource documentation"
  - "website/docs"
---

# Provider Documentation

Documentation lives under `website/docs/` and is published to the Terraform Registry. Doc changes must be in the same PR as the schema/code changes they document.

## Doc Type → Path Mapping

| Type | Path |
|---|---|
| Resource | `website/docs/r/<service>_<resource_name>.html.markdown` |
| Data Source | `website/docs/d/<service>_<resource_name>.html.markdown` |
| Action | `website/docs/actions/<service>_<action_name>.html.markdown` |
| Provider Function | `website/docs/functions/<function_name>.html.markdown` |
| Ephemeral Resource | `website/docs/ephemeral-resources/<service>_<resource_name>.html.markdown` |
| List Resource | `website/docs/list-resources/<service>_<resource_name>.html.markdown` |

---

## Resource Template

`website/docs/r/<service>_<resource_name>.html.markdown`

```markdown
---
subcategory: "<Service Category>"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_<resource_name>"
description: |-
  Manages a <Resource>.
---

# azurerm_<resource_name>

Manages a <Resource>.

## Example Usage

```hcl
resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_<resource_name>" "example" {
  name                = "example"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
}
```

## Arguments Reference

The following arguments are supported:

* `location` - (Required) The Azure Region where the <Resource> should exist. Changing this forces a new <Resource> to be created.

* `name` - (Required) The name which should be used for this <Resource>. Changing this forces a new <Resource> to be created.

* `resource_group_name` - (Required) The name of the Resource Group in which to create the <Resource>. Changing this forces a new <Resource> to be created.

---

* `<optional_arg>` - (Optional) <Description>.

* `tags` - (Optional) A mapping of tags which should be assigned to the <Resource>.

## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the <Resource>.

## Timeouts

The `timeouts` block allows you to specify [timeouts](https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts) for certain actions:

* `create` - (Defaults to X minutes) Used when creating the <Resource>.
* `read` - (Defaults to 5 minutes) Used when retrieving the <Resource>.
* `update` - (Defaults to X minutes) Used when updating the <Resource>.
* `delete` - (Defaults to X minutes) Used when deleting the <Resource>.

## Import

<Resource>s can be imported using the `resource id`, e.g.

```shell
terraform import azurerm_<resource_name>.example /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.<Namespace>/<ResourceType>/<name>
```
```

**Rules:**
- Required arguments are listed before the `---` separator.
- Optional arguments are listed after the `---` separator.
- The `id` attribute is always present in Attributes Reference.
- Timeouts block is always present with at least `read`.
- Import block uses a real ARM ID example with zeroed subscription GUID.

---

## Data Source Template

`website/docs/d/<service>_<resource_name>.html.markdown`

```markdown
---
subcategory: "<Service Category>"
layout: "azurerm"
page_title: "Azure Resource Manager: Data Source: azurerm_<resource_name>"
description: |-
  Gets information about an existing <Resource>.
---

# Data Source: azurerm_<resource_name>

Use this data source to access information about an existing <Resource>.

## Example Usage

```hcl
data "azurerm_<resource_name>" "example" {
  name                = "existing"
  resource_group_name = "existing-resource-group"
}

output "id" {
  value = data.azurerm_<resource_name>.example.id
}
```

## Arguments Reference

The following arguments are supported:

* `name` - (Required) The Name of this <Resource>.

* `resource_group_name` - (Required) The name of the Resource Group in which this <Resource> exists.

## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the <Resource>.

## Timeouts

The `timeouts` block allows you to specify [timeouts](https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts) for certain actions:

* `read` - (Defaults to 5 minutes) Used when retrieving the <Resource>.
```

**Rules:**
- Description starts: "Gets information about an existing..."
- H1 prefix: `# Data Source:`
- Only a `read` timeout.
- No Import section.

---

## Action Template

`website/docs/actions/<service>_<action_name>.html.markdown`

```markdown
---
subcategory: "<Service Category>"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_<action_name>"
description: |-
  <Brief description of what the action does>.
---

# Action: azurerm_<action_name>

<Description of what the action does>.

## Example Usage

```terraform
resource "azurerm_<resource>" "example" {
  # ... resource configuration
}

resource "terraform_data" "example" {
  input = azurerm_<resource>.example.id

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.azurerm_<action_name>.example]
    }
  }
}

action "azurerm_<action_name>" "example" {
  config {
    <resource>_id = azurerm_<resource>.example.id
    <param>       = "<value>"
  }
}
```

## Argument Reference

This action supports the following arguments:

* `<resource>_id` - (Required) The ID of the <resource> on which to perform the action.

* `<param>` - (Required) <Description>. Possible values include `<value1>` and `<value2>`.
```

**Rules:**
- H1 prefix: `# Action:`
- Example Usage must show the `action_trigger` block on a `terraform_data` resource.
- No Timeouts section.
- No Import section.

---

## Provider Function Template

`website/docs/functions/<function_name>.html.markdown`

```markdown
---
subcategory: ""
layout: "azurerm"
page_title: "Azure Resource Manager: <function_name>"
description: |-
  <Brief description of what the function does>.
---

# Function: <function_name>

~> **Note:** Provider-defined functions are supported in Terraform 1.8 and later, and are available from version 4.0 of the provider.

<Description of what the function does>.

## Example Usage

```hcl
output "result" {
  value = provider::azurerm::<function_name>(<arg>)
}
```

## Signature

```text
<function_name>(<arg> <type>) <return_type>
```

## Arguments

1. `<arg>` (<Type>) <Description>.
```

**Rules:**
- `subcategory` is always `""` for functions.
- Always include the Terraform 1.8 / provider 4.0 version note.
- Arguments are a numbered list, not a bullet list.
- No Timeouts section.
- No Import section.

---

## Ephemeral Resource Template

`website/docs/ephemeral-resources/<service>_<resource_name>.html.markdown`

```markdown
---
subcategory: "<Service Category>"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_<resource_name>"
description: |-
  Gets information about an existing <Resource>.
---

# Ephemeral: azurerm_<resource_name>

~> **Note:** Ephemeral Resources are supported in Terraform 1.10 and later.

Use this to access information about an existing <Resource>.

## Example Usage

```hcl
ephemeral "azurerm_<resource_name>" "example" {
  name         = "example"
  <parent>_id  = azurerm_<parent>.example.id
}
```

## Argument Reference

The following arguments are supported:

* `name` - (Required) Specifies the name of the <Resource>.

* `<parent>_id` - (Required) Specifies the ID of the <parent resource>.

## Attributes Reference

The following attributes are exported:

* `<attr>` - <Description>.
```

**Rules:**
- H1 prefix: `# Ephemeral:`
- Always include the Terraform 1.10 note.
- Description same wording as data source ("Gets information about an existing...").
- Section heading is `# Argument Reference` (not `# Arguments Reference`).
- No Timeouts section.
- No Import section.

---

## List Resource Template

`website/docs/list-resources/<service>_<resource_name>.html.markdown`

```markdown
---
subcategory: "<Service Category>"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_<resource_name>"
description: |-
  Lists <Resource> resources.
---

# List resource: azurerm_<resource_name>

Lists <Resource> resources.

## Example Usage

### List all <Resource>s in the subscription

```hcl
list "azurerm_<resource_name>" "example" {
  provider = azurerm
  config {
  }
}
```

### List all <Resource>s in a Resource Group

```hcl
list "azurerm_<resource_name>" "example" {
  provider = azurerm
  config {
    resource_group_name = "example-rg"
  }
}
```

## Argument Reference

This list resource supports the following arguments:

* `subscription_id` - (Optional) The ID of the Subscription to query. Defaults to the value specified in the Provider Configuration.

* `resource_group_name` - (Optional) The name of the Resource Group to query.
```

**Rules:**
- H1 prefix: `# List resource:`
- Always show at least two Example Usage variants: subscription-wide and resource-group-scoped.
- Description is always "Lists <X> resources."
- No Timeouts section.
- No Import section.

---

## Quality Rules (All Types)

- Doc changes must be in the same PR as the schema/code changes they document.
- Examples must compile as valid HCL and use current argument/attribute names.
- Never describe arguments or attributes that are not implemented.
- Keep examples minimal — show what's needed to create/use the resource, not every optional property.
- Deprecation notes use the `->` callout syntax: `-> **Note:** This resource has been deprecated...`
- Breaking change notes that are not yet active (gated behind `features.FivePointOh()`) must **not** appear in the documentation.
