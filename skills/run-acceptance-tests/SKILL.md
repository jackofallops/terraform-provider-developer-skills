---
name: run-acceptance-tests
description: Run and diagnose acceptance tests for terraform-provider-azurerm. Use when asked to run a TestAcc test, investigate a test failure, or set up a VCR replay.
triggers:
  - "run acceptance test"
  - "run TestAcc"
  - "diagnose test failure"
  - "VCR replay"
---

# Run Acceptance Tests

Acceptance tests are Go tests with the `TestAcc` prefix. They make real API calls and incur cost. **Unit tests do not require credentials and can be run freely.**

## Credential Requirement

Acceptance tests require Azure credentials via `ARM_*` environment variables. **If these are not explicitly available to the agent, do not attempt to run acceptance tests directly.** Instead, ask the user to run the test and return the output.

This applies to:

- All `TestAcc*` tests
- Any test that touches Azure APIs or requires authentication

Unit tests (no `TestAcc` prefix) do not require credentials and can be run without asking.

## Running a Test

```bash
TF_ACC=1 go test \
  -run=TestAccExampleResource_basic \
  -timeout 120m \
  ./internal/services/<service>/...
```

- Always set `-timeout` — azurerm acceptance tests can take 60–120 minutes.
- The test name must match exactly (case-sensitive, supports regex).

## VCR Replay Mode (Preferred — No API Calls, No Cost)

If a valid cassette exists for the test, run in replay mode to avoid real API calls:

```bash
TC_TEST_VIA_VCR=replay \
VCR_PATH=<path-to-cassettes> \
go test \
  -run=TestAccExampleResource_basic \
  -timeout 10m \
  ./internal/services/<service>/...
```

Always check whether a cassette exists before running in live mode. If unsure, ask the user.

## Diagnosing a Failing Test

Apply these steps in order. Each step includes all previous options:

1. **Avoid cached results** — add `-count=1`:

   ```bash
   TF_ACC=1 go test -run=TestAccX -count=1 -timeout 120m ./internal/services/<service>/...
   ```

2. **Verbose output** — add `-v`:

   ```bash
   TF_ACC=1 go test -run=TestAccX -count=1 -v -timeout 120m ./internal/services/<service>/...
   ```

3. **Debug logging** — set `TF_LOG=debug`:

   ```bash
   TF_ACC=1 TF_LOG=debug go test -run=TestAccX -count=1 -v -timeout 120m ./internal/services/<service>/...
   ```

4. **Persist workspace** — set `TF_ACC_WORKING_DIR_PERSIST=1` to inspect the Terraform state and plan files after the run:

   ```bash
   TF_ACC=1 TF_LOG=debug TF_ACC_WORKING_DIR_PERSIST=1 go test -run=TestAccX -count=1 -v -timeout 120m ./internal/services/<service>/...
   ```

## Verifying a Passing Test Is Not a False Negative

To confirm a passing test actually exercises the assertion:

1. Edit the expected value in one of the `check.That(...).Key(...).HasValue(...)` calls to an incorrect value.
2. Run the test — it should fail.
3. If it fails, revert the edit and report a confirmed flip. If it does not fail, keep the edit and report the test as not exercising that assertion.
