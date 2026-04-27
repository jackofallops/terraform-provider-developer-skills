---
name: terraform-dag
description: Understand Terraform's execution engine as a concurrent scheduler and distinguish between logic errors in Provider code (Go) and race conditions caused by the Directed Acyclic Graph (DAG) during TestAcc runs.
triggers:
  - "DAG race condition"
  - "parallel test failure"
  - "concurrency bug"
  - "VCR cassette mismatch"
---

# Terraform Provider Concurrency & DAG Logic

The agent understands Terraform's execution engine as a concurrent scheduler. It can distinguish between logic errors in Provider code (Go) and race conditions caused by the Directed Acyclic Graph (DAG) during `TestAcc` runs.

## Core Concepts for Provider Debugging

### 1. The Parallel Execution Enabler (The DAG)
* **The Scheduler:** Terraform walks the DAG and identifies "independent branches." If a test config defines five `aws_instance` resources without dependencies, the Provider's `Create` function will be called 5 times concurrently (up to the default `-parallelism=10`).
* **Isolation Guarantee:** In a single walk, resource $A$ cannot pass data to resource $B$ of the same type unless an edge (dependency) exists.
* **Provider gRPC Boundary:** The agent must recognize that while the Provider is a single process, the `terraform-plugin-framework` (or SDKv2) handles these CRUD calls in separate goroutines.



### 2. Debugging Heuristics (Provider vs. HCL)
When analyzing test failures (e.g., `TestAccExample_basic`), the agent must apply these rules:

| Symptom | Likely Cause | Debugging Action |
| :--- | :--- | :--- |
| `ResourceNotFound` during parallel Create | **API Race Condition.** The backend API hasn't propagated the first resource before the second one tries to reference it. | Suggest adding `time.Sleep` in the provider or a `depends_on` in the test HCL to verify. |
| Interleaved Logs in `TF_LOG=TRACE` | **Parallel Execution.** Logs from `Create` for Resource A and Resource B are mixing. | Identify the `[root]` or `[id]` in logs to untangle which thread is failing. |
| Consistent failure on `-parallelism=1` but pass on default | **Logic Error.** The code depends on a side effect of concurrency. | (Rare) Check for global variables/shared state in the provider struct. |
| Random failure on default but pass on `-parallelism=1` | **Concurrency Bug.** The provider is not thread-safe or the API is rate-limiting concurrent writes. | Check mutexes in the `client` or `provider` struct. |

### 3. Acceptance Test Isolation
* `helper/resource.ParallelTest` runs entire test cases in parallel with other tests.
* A single `resource.Test` with multiple resources in one `Step` runs those resources in parallel based on the DAG.

## Execution Constraints
* **No Implicit Ordering:** Never assume `Resource_A` will finish before `Resource_B` if they are the same type in the same test step.
* **State Consistency:** Assume that during a parallel walk, the `State` for one resource is "locked" to that CRUD operation and cannot be modified by a neighboring resource thread.


### VCR Cassette Interpretation
* **Interleaved Streams:** Recognize that a single `.yaml` cassette contains multiple interleaved HTTP streams.
* **Deterministic Matching:** When analyzing Go code using `go-vcr`, prioritize looking at the `vcr.Config.Matcher`. If the Provider sends a `User-Agent` with a version string or a `Request-ID`, the agent must suggest ignoring these headers in the matcher to ensure replay stability.
* **State vs. Cassette:** If the `ID` in the Terraform State doesn't match the `id` in the VCR Cassette, the "Parallel Execution Enabler" will fail because the DAG will attempt to pass an ID to a dependency that "doesn't exist" in the recorded world.