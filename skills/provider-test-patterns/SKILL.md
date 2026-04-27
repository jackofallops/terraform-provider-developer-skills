---
name: provider-test-patterns
description: Write acceptance tests for azurerm resources following the established test structure and patterns.
triggers:
  - "write acceptance tests"
  - "add tests"
  - "test patterns"
  - "TestAcc"
---

# Provider Test Patterns

This skill covers writing acceptance tests for `terraform-provider-azurerm`. Tests use the `acceptance` package wrapper, which handles the majority of test setup boilerplate.

## Mandatory Test Types

Every resource must have the following three tests as a baseline. Propose them in this order:

| Test | Config scope | Purpose |
|---|---|---|
| `basic` | All `Required` properties only | Confirms the minimum viable configuration works end-to-end |
| `complete` | All `Required` + `Optional` properties | Confirms all properties are correctly sent, read back, and stored in state |
| `requiresImport` | Extends `basic` config | Exercises the `resourceRequiresImport` error path in `Create` |

> **Cost note:** If the user requests full property-matrix coverage (e.g. every Optional property tested in isolation), call out that this will generate a large number of tests and real API calls. Let them make an informed decision on coverage versus cost.

## Test Function Structure

```go
func TestAccExampleResource_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example", "test")
    r := ExampleResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basicConfig(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
                check.That(data.ResourceName).Key("name").HasValue(data.RandomString),
            ),
        },
        data.ImportStep(),
    })
}

func TestAccExampleResource_complete(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example", "test")
    r := ExampleResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.completeConfig(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.ImportStep(),
    })
}

func TestAccExampleResource_requiresImport(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example", "test")
    r := ExampleResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basicConfig(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.RequiresImportErrorStep(r.requiresImportConfig),
    })
}
```

`acceptance.BuildTestData` generates VCR-safe deterministic names and provides the `ResourceName` address. Use it — do not call `uuid.New()` or `time.Now()` directly in test configs.

## Provider Factories

Standard resource tests use the factories already provided by the `acceptance` package — do not declare `ProtoV5ProviderFactories` explicitly. The explicit factory is only needed for:
- List Resources
- Actions
- Ephemeral Values

## Import Step

`data.ImportStep()` performs an ID-only import with no config and verifies the imported state matches the prior state. Add `ImportStateVerifyIgnore` only for values that **cannot be recovered from a GET using the resource ID** — for example, write-only properties like passwords or client secrets that the API does not return.

```go
data.ImportStep("admin_password", "client_secret")
```

Do not ignore properties simply because they are sensitive — only ignore them if they are genuinely unreadable after creation.

## Disappears Test

> **Note:** This test pattern is under consideration for deprecation in the provider. Include it only if explicitly requested or if the resource's existing test suite already contains one.

```go
func TestAccExampleResource_disappears(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example", "test")
    r := ExampleResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        data.DisappearsStep(acceptance.DisappearsStepData{
            Config:       r.basicConfig,
            TestResource: r,
        }),
    })
}
```

## Composing Check Functions

Use `acceptance.ComposeTestCheckFunc` (fails on first error) for standard checks. Use `acceptance.ComposeAggregateTestCheckFunc` when you want all failures reported in one run — useful during active debugging.

## Config Helpers

Config functions are methods on the resource test struct. Reference `basic` config from `requiresImport` to avoid duplication:

```go
func (r ExampleResource) basicConfig(data acceptance.TestData) string {
    return fmt.Sprintf(`
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "test" {
  name     = "acctestRG-%[1]d"
  location = "%[2]s"
}

resource "azurerm_example" "test" {
  name                = "acctestex%[1]d"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location
}
`, data.RandomInteger, data.Locations.Primary)
}

func (r ExampleResource) requiresImportConfig(data acceptance.TestData) string {
    return fmt.Sprintf(`
%s

resource "azurerm_example" "import" {
  name                = azurerm_example.test.name
  resource_group_name = azurerm_example.test.resource_group_name
  location            = azurerm_example.test.location
}
`, r.basicConfig(data))
}
```

## Regression Test Pattern

When fixing a bug, use the two-commit workflow:
1. **First commit:** Add the failing regression test (it should fail at this point, confirming the bug).
2. **Second commit:** Add the fix (test passes).

Name regression tests clearly and link to the issue:

```go
// TestAccExampleResource_regressionGH12345 verifies the fix for
// https://github.com/hashicorp/terraform-provider-azurerm/issues/12345
func TestAccExampleResource_regressionGH12345(t *testing.T) {
    // ...
}
```

## Pre-Submission Checklist

- [ ] `basic`, `complete`, and `requiresImport` tests exist
- [ ] `acceptance.BuildTestData` used — no raw `uuid` or `time.Now` calls in configs
- [ ] `ImportStateVerifyIgnore` justified (only for truly unrecoverable values)
- [ ] Config helpers are methods on the resource test struct
- [ ] `resource.ParallelTest` used (via `data.ResourceTest`) — not `resource.Test` unless explicitly sharing state
- [ ] Regression tests named and linked to issue
