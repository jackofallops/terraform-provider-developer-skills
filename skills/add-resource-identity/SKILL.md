---
name: add-resource-identity
description: Assist in adding Resource Identity to a provider resource.
---

# `add-resource-identity`

This skill provides step-by-step instructions for implementing Resource Identity for an AzureRM resource. Resource Identity validates that the ID parts match the resource schema and state accurately, and is required for some features like `List Resources`.

## Step 1: Add the Identity Definition to the Schema

In your `*pluginsdk.Resource` definition (typically in `<resource>_resource.go`), add the `Identity` field. This points to an Identity Schema struct (usually an SDK-generated `Id` object):

```go
func resourceMyResource() *pluginsdk.Resource {
	return &pluginsdk.Resource{
		// ... existing methods
		
		Importer: pluginsdk.ImporterValidatingIdentity(&myservice.Id{}),

		Identity: &schema.ResourceIdentity{
			SchemaFunc: pluginsdk.GenerateIdentitySchema(&myservice.Id{}),
		},
```
Make sure `&myservice.Id{}` matches the ID struct type used by the `go-azure-sdk` client for this resource.

## Step 2: Ensure Data is Set During Operations

In the resource's `Create`, `Read`, and `Update` methods, ensure you save the identity data back to the resource state using `pluginsdk.SetResourceIdentityData`:

```go
if err := pluginsdk.SetResourceIdentityData(d, id); err != nil {
	return fmt.Errorf("setting resource identity: %w", err)
}
```

## Step 3: Add the Generator Instruction

We use `go generate` to automatically create the Resource Identity Acceptance Test. Add a `//go:generate` comment near the top of the resource's `.go` file (e.g., `internal/services/<service>/<resource>_resource.go`).

### Basic Usage

```go
//go:generate go run ../../tools/generator-tests resourceidentity -resource-name <resource_name> -properties "<comma_separated_properties>"
```

### Generator Flags and Options

The generator (`internal/tools/generator-tests/generators/resource_identity.go`) supports several flags to customize how the test is built:

- `-resource-name` **(Required)**: The name of the resource (without the `azurerm_` prefix). Example: `application_insights`.
- `-properties` **(Required)**: Comma-separated list of schema properties making up the Resource Identity (do not include implicit properties like `subscription_id`). If the ID property name and the schema name differ, map them using `<id_name>:<schema_name>`.
- `-known-values` (Optional): Comma-separated list of known discriminated values formatted as `<name>:<value>`. E.g., `subscription_id:data.Subscriptions.Primary`. (Note: If your value needs a literal comma, use a semicolon instead, e.g. `kind:linux;functionapp` will be parsed as `kind:linux,functionapp`).
- `-compare-values` (Optional): Resource identity parts that are embedded within a different schema property (like a parent ID). E.g., `parent_name:parent_resource_id,resource_group_name:parent_resource_id`.
- `-no-subscription-id` (Optional): Omit the default `subscription_id` validation check. Automatically inferred if you specify `subscription_id` in `-known-values` or `-compare-values`.
- `-test-name` (Optional): The acceptance test configuration method to use (e.g. `r.basicForResourceIdentity(...)`). Defaults to `basic`.
- `-test-params` (Optional): Additional parameters to pass to the test configuration function (e.g., `-test-params "B1"`).
- `-test-expect-non-empty` (Optional): Expect (and ignore) a non-empty plan during import checks (used if the API doesn't return certain values, causing a diff after import).
- `-test-sequential` (Optional): Generate a sequential test instead of a parallel one.
- `-service-package-name` (Optional): The directory name of the service package (default is the current directory).

### Example Implementations

**Standard with known subscription ID:**
```go
//go:generate go run ../../tools/generator-tests resourceidentity -resource-name batch_account -properties "name,resource_group_name" -known-values "subscription_id:data.Subscriptions.Primary"
```

**With differing property names:**
```go
//go:generate go run ../../tools/generator-tests resourceidentity -resource-name batch_pool -properties "name,resource_group_name,batch_account_name:account_name" -known-values "subscription_id:data.Subscriptions.Primary"
```

**Using a parent ID reference in the schema (compare-values):**
```go
//go:generate go run ../../tools/generator-tests resourceidentity -resource-name dedicated_host -properties "name" -compare-values "subscription_id:dedicated_host_group_id,resource_group_name:dedicated_host_group_id,host_group_name:dedicated_host_group_id"
```

**Custom Test Name with Parameters:**
```go
//go:generate go run ../../tools/generator-tests resourceidentity -resource-name linux_function_app -properties "name,resource_group_name" -test-params "B1" -known-values "subscription_id:data.Subscriptions.Primary"
```

## Step 4: Run Go Generate

After defining the directive, run `go generate` from the service directory to generate the `<resource>_resource_identity_gen_test.go` file:

```sh
cd internal/services/<service>
go generate <resource>_resource.go
```
(Or run it via `make generate` to regenerate all files provider-wide).
