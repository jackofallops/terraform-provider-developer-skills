---
name: terraform-test-config-cleanup
description: Clean up, tidy, or refactor the HCL config functions in a Terraform provider acceptance test file (e.g. *_resource_test.go).
triggers:
  - "fix acceptance test configs"
  - "clean up test configs"
  - "refactor test configs"
---

# Terraform Test Config Cleanup

Refactor the config methods in a Terraform provider acceptance test file so they follow the provider's preferred conventions.

Applies to every config method (`basic`, `complete`, `update`,`requiresImport`, `template`, etc.) in the file.

## Step 1 - Inline intermediate variables

If a method assigns a helper result to a local variable only to pass it into a
single `fmt.Sprintf`, drop the variable and pass the call directly.

Before:

```go
func (r Resource) basic(data acceptance.TestData) string {
	template := r.template(data)
	return fmt.Sprintf(`
%s

resource "..." "test" {
  name = "acctest-%d"
}
`, template, data.RandomInteger)
}
```

After:

```go
func (r Resource) basic(data acceptance.TestData) string {
	return fmt.Sprintf(`
%[1]s

resource "..." "test" {
  name = "acctest-%[2]d"
}
`, r.template(data), data.RandomInteger)
}
```

This applies equally to variables named `config`, `template`, or similar that are used exactly once as a `fmt.Sprintf` argument. 

Do NOT inline a variable that is referenced more than once or used for anything other than the single `fmt.Sprintf` call.

## Step 2 - Convert bare verbs to indexed verbs

Replace every bare verb with its indexed form, numbered by argument position (1-based) in the `fmt.Sprintf` argument list:

- `%s` -> `%[1]s`, `%d` -> `%[2]d`, etc., matching argument order.
- When the same argument is used multiple times in the string (e.g.`data.RandomInteger` appearing twice), point every occurrence at the same index and **remove the duplicated trailing arguments** so each argument appears once.

Example deduplication:

```go
// before
`... %d ... %s ... %d`, data.RandomInteger, data.Locations.Primary, data.RandomInteger)
// after
`... %[1]d ... %[2]s ... %[1]d`, data.RandomInteger, data.Locations.Primary)
```

## Procedure

1. Read the whole test file.
2. For each config method:
   - Inline any single-use `template`/`config` variable into `fmt.Sprintf`.
   - Rewrite all verbs as indexed verbs based on argument position.
   - Deduplicate repeated arguments, collapsing them to a shared index.
3. Verify the result:
   - `gofmt -l <file>` (should print nothing)
   - `go vet ./<package-dir>/` (catches Sprintf arg-count/verb mismatches, note that this doesn't catch unused arguments)
4. Preserve the exact HCL content, whitespace, and formatting otherwise.
