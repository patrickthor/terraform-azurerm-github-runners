# Function App Deployment Notes

## Deployment Method

Deploy using `az functionapp deployment source config-zip` with a self-contained zip. This is the recommended method for Python on Flex Consumption (FC1).

```bash
cd scaler-function
pip install --target=".python_packages/lib/site-packages" -r requirements.txt
zip -r ../deploy.zip . -x "local.settings*.json" -x "__pycache__/*" -x "*.pyc" -x "DEPLOYMENT.md"
cd ..

az functionapp deployment source config-zip \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw function_app_name)" \
  --src deploy.zip --timeout 300
```

The CI/CD workflow handles this automatically, including temporarily whitelisting the runner's IP through the Function App's IP restrictions.

---

## Known Issues & Fixes

### 1. Functions not registered after deploy (zero functions discovered)
**Symptom**: `Functions in <app>:` shows empty list after publish.
**Cause**: A module-level exception in `function_app.py` silently prevents all function registrations. The host shows no error.
**Fix**: Ensure all decorator usage is standard `@app.timer_trigger(...)` syntax. Imperative reversed-decorator patterns (`app.function_name(...)(fn)` before the trigger decorator) throw at import time.

### 2. Cleanup timer not deleting terminated containers
**Symptom**: Containers stuck in `Succeeded`/`Terminated` state indefinitely.
**Cause**: The ARM List API (`GET /containerGroups`) does **not** return `instanceView`. Only individual `GET /containerGroups/{name}` does.
**Fix**: `_list_runners()` now calls individual GETs for each container to get full state. `_runner_state()` also falls back to `containers[0].instanceView.currentState.state`.

### 3. Multiple containers created for a single job
**Symptom**: One webhook event results in 2–3 container instances being created.
**Cause 1**: `host.json` defaulted `maxConcurrentCalls` to 16, causing parallel `scale_worker` executions that all read 0 runners simultaneously.
**Fix**: Set `maxConcurrentCalls: 1` in `host.json` to serialize scale decisions.
**Cause 2**: Scale formula used `scale_hint + queue_backlog` — when 1 message was in-flight and 1 was waiting, desired became 2.
**Fix**: Changed to `max(scale_hint, queue_backlog)`. Each message gets its own serialized invocation, so the next invocation handles the next job.

### 4. Webhook not triggering runner creation
**Symptom**: GitHub Actions job queued but no container created, no webhook hit in App Insights.
**Cause**: GitHub webhook misconfigured (wrong URL, wrong event type, or missing `self-hosted` label on the workflow job).
**Fix**:
- Webhook URL format: `https://<hostname>/api/webhook/github?code=<function_key>`
- Content type: `application/json`
- Event: **Workflow jobs** only
- Workflow must use `runs-on: [self-hosted, ...]` — jobs without `self-hosted` label are ignored by the function

---

## Retrieving the Webhook URL

```bash
RG=$(terraform output -raw resource_group_name)
FUNC=$(terraform output -raw function_app_name)
HOST=$(terraform output -raw function_app_default_hostname)

KEY=$(az functionapp function keys list -g "$RG" -n "$FUNC" \
  --function-name github_webhook --query default -o tsv)
echo "https://${HOST}/api/webhook/github?code=$KEY"
```

---

## Verifying Deployment

After deploy, confirm all three functions appear:
```
Functions in <app>:
    cleanup_timer - [timerTrigger]
    github_webhook - [httpTrigger]
    scale_worker   - [serviceBusTrigger]
```

If any are missing, check for module-level import errors (see issue #1).
