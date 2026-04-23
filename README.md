# terraform-provider-developer-skills

A collection of skills for assisting in Terraform Provider Development against both `terraform-plugin-sdk` and `terraform-plugin-framework`. These skills are designed to be consumed by AI Agents to enhance their capabilities and align them with provider-specific best practices.

## Available Skills

| Skill | Description |
|---|---|
| **deprecate-property** | Assist in deprecating or renaming a property, following the breaking changes guide. |
| **deprecate-resource** | Assist in deprecating an existing resource or data source, following the breaking changes guide. |
| **modify-native-resource** | Assist in adding a new property to an existing legacy resource (native Plugin SDK). |
| **modify-typed-resource** | Assist in adding a new property to an existing legacy resource (Typed SDK wrapper). |
| **resource-framework-migration** | Assist in migrating resources from `terraform-plugin-sdk` (legacy) to `terraform-plugin-framework` using the `internal/sdk` wrapper. |
| **state-upgrade-required** | Assist in creating a resource state migration for updating the schema and its values in a Terraform resource that uses `terraform-plugin-sdk` v2. |
| **terraform-dag** | Understand Terraform's execution engine as a concurrent scheduler and distinguish between logic errors and DAG race conditions. |

## Installation (Agent Package Manager)

This repository includes an `apm.yml` (Agent Package Manager) manifest, allowing you to easily pull these skills into your projects for your AI Agents to leverage.

### Using Node.js (npx)

If your environment supports Node.js, you can install the skills directly using `npx`:

```bash
npx @agent-package-manager/cli install https://github.com/jackofallops/terraform-provider-developer-skills.git
```

### Using an Agent CLI

For AI agents that natively support the APM specification, use their built-in CLI `install` command:

```bash
agent install https://github.com/jackofallops/terraform-provider-developer-skills.git
```

This will parse the `apm.yml` manifest, install the configured capabilities, and run any post-install hooks to optimize your agent for Go and Terraform SDK development.

### Manual Integration

If you aren't using an APM-compatible package manager, you can manually drop the skills directly into your project's agent context directory (such as `.agent/skills/` or `.cursor/rules/`) so your assistant can parse the `.md` instructions directly:

