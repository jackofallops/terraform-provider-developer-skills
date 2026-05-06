---
name: custom-poller-migration
description: Assist in migrating legacy pluginsdk.Retry() and pluginsdk.StateChangeConf.WaitForStateContext() logic to custom pollers.
triggers:
  - "replace legacy retry"
  - "migrate to custom poller"
  - "remove WaitForStateContext"
  - "replace StateChangeConf with poller"
---

# Custom Poller Migration Skill

This skill guides you through replacing legacy `pluginsdk.Retry()` and `pluginsdk.StateChangeConf` blocks with custom pollers using `pollers.PollerType`. This is essential to remove `pluginsdk` dependencies from our API interaction layers and transition to the native polling mechanisms available in the `go-azure-sdk`.

## 1. Identification

You might encounter two types of legacy polling mechanisms:

### A. Legacy `pluginsdk.Retry()`

This loop repeatedly runs a function until it succeeds or hits a non-retryable error, often checking for `400 BadRequest`.

```go
err = pluginsdk.Retry(d.Timeout(pluginsdk.TimeoutCreate), func() *pluginsdk.RetryError {
    resp, err := client.CreateOrUpdate(ctx, id, params)
    if err != nil {
        if response.WasBadRequest(resp.HttpResponse) {
            return pluginsdk.RetryableError(err) // Retries
        }
        return pluginsdk.NonRetryableError(err) // Fails immediately
    }
    // Success path...
    return nil
})
```

### B. Legacy `pluginsdk.StateChangeConf`

This structure polls an API via `Refresh` until the HTTP response status matches a `Target` list, remaining in a `Pending` state otherwise.

```go
stateConf := &pluginsdk.StateChangeConf{
    Pending: []string{"404"},
    Target:  []string{"200"},
    Refresh: func() (interface{}, string, error) {
        resp, err := client.Get(ctx, id)
        if err != nil {
            if response.WasNotFound(resp.HttpResponse) {
                return resp, strconv.Itoa(resp.HttpResponse.StatusCode), nil
            }
            return nil, "0", fmt.Errorf("polling for %s: %+v", id, err)
        }
        return resp, strconv.Itoa(resp.HttpResponse.StatusCode), nil
    },
    // timeouts, intervals...
}
if _, err := stateConf.WaitForStateContext(ctx); err != nil {
    return err
}
```

## 2. Implementing a Custom Poller

A custom poller must implement the `pollers.PollerType` interface, specifically the `Poll(ctx context.Context) (*pollers.PollResult, error)` method.

Create your poller typically in a `custompollers` package within the relevant service directory.

### Structure Example

```go
package custompollers

import (
    "context"
    "fmt"
    "net/http"
    "time"

    "github.com/hashicorp/go-azure-sdk/sdk/client/pollers"
    // import service client
)

var _ pollers.PollerType = &examplePoller{}

type examplePoller struct {
    client *service.Client
    id     service.IdType
}

func NewExamplePoller(cli *service.Client, id service.IdType) *examplePoller {
    return &examplePoller{
        client: cli,
        id:     id,
    }
}
```

### The `Poll` Implementation

> [!CAUTION]
> **No Global `PollResult` Variables!**
> To prevent severe concurrency bugs across parallel test executions and apply operations, you **must always return a new `pollers.PollResult{}` struct directly**. Do not use package-level variables like `var pollingSuccess = pollers.PollResult{}` as was historically done in some older pollers.

```go
func (p examplePoller) Poll(ctx context.Context) (*pollers.PollResult, error) {
    // 1. Execute the check (e.g., Get or repeated CreateOrUpdate)
    resp, err := p.client.Get(ctx, p.id)

    // 2. Evaluate errors (if translating from Retry or StateChangeConf)
    if err != nil {
        if response.WasNotFound(resp.HttpResponse) {
            // Equivalent to a "404" Pending state in StateChangeConf
            return &pollers.PollResult{
                Status:       pollers.PollingStatusInProgress,
                PollInterval: 10 * time.Second, // Match original logic exactly
            }, nil
        }
        // Terminal error
        return nil, fmt.Errorf("checking state: %+v", err)
    }

    // 3. Evaluate success states
    if resp.StatusCode == http.StatusOK {
        // Equivalent to "200" Target state
        return &pollers.PollResult{
            Status:       pollers.PollingStatusSucceeded,
            PollInterval: 10 * time.Second,
        }, nil
    }

    return nil, fmt.Errorf("unexpected status code %d", resp.StatusCode)
}
```

## 3. Behavioral Parity

> [!IMPORTANT]
> **Strict Equivalency:** The polling interval, the timeout constraints (where possible via context), the terminal error cases, and the exact HTTP status codes used to determine `Pending` versus `Target` **must exactly match** the legacy implementation.

If you discover that the legacy `Retry` or `StateChangeConf` block contains an obvious bug (e.g., catching `400 BadRequest` infinitely on a static payload with no side effects), **DO NOT fix it silently**. You must document the flaw in your implementation plan and await user approval before altering the provider's established behavior.

## 4. Integration

Replace the old logic with your new custom poller.

### To invoke it directly

Instead of `stateConf.WaitForStateContext(ctx)`:

```go
import "github.com/hashicorp/go-azure-sdk/sdk/client/pollers"

// ... inside resource function ...
poller := custompollers.NewExamplePoller(client, id)
if err := pollers.PollUntilDone(ctx, poller); err != nil {
    return fmt.Errorf("waiting for state: %+v", err)
}
```

### For operations returning a `resp.Poller`

If you are wrapping the initial API operation directly and providing a poller struct to the client pipeline:

```go
// Invoke initial operation (which is wired up to return your custom poller)
resp, err := client.CreateOrUpdate(ctx, id, params)
if err != nil {
    return fmt.Errorf("creating resource: %+v", err)
}

if err := resp.Poller.PollUntilDone(ctx); err != nil {
    return fmt.Errorf("waiting for completion: %+v", err)
}
```
