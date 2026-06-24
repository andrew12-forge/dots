Trigger a Forge cloud build for a chime-disputes worktree.

Arguments: $ARGUMENTS (space-separated, both optional)
- First arg: bug number (e.g. "67")
- Second arg: entry point function name (e.g. "fraud_signals_denial_codes_arbitrary_transactions")

Examples:
- `/forge-run 71` → bug 71, default entry point `run_test_cases_dev`
- `/forge-run 71 fraud_signals_denial_codes_arbitrary_transactions` → bug 71, custom entry point
- `/forge-run` → infer bug number from cwd, default entry point

## Step 1: Parse arguments

Split `$ARGUMENTS` on whitespace. The first token (if numeric) is the bug number. The second token (if present) is the entry point function name. If no entry point is provided, default to `run_test_cases_dev`.

If the first token is not a number, extract the bug number from the current working directory. Look for a `bug-<N>` pattern in the path. For example `/Users/andrew/_dev/chime-disputes-worktrees/bug-67` → bug number `67`.

If neither yields a bug number, ask the user which bug number to use.

## Step 2: Resolve worktree path

```
WORKTREE=/Users/andrew/_dev/chime-disputes-worktrees/bug-<N>
```

Verify the directory exists with `ls`. If it doesn't exist, tell the user and stop.

## Step 3: Run `sand build`

Run this in the worktree directory to regenerate the executor definition. Use two separate Bash calls (do NOT chain with `&&`, as that prevents permission auto-approval):

1. `cd <WORKTREE>`
2. `sand build`

If it fails, show the error and stop.

## Step 4: Read Forge session cookie from Redis

```bash
python3 -c "import redis; r = redis.Redis(host='localhost', port=6379, decode_responses=True); print(r.get('cookie:forge_session'))"
```

If `redis-cli` is available on PATH, you can use `redis-cli get cookie:forge_session` instead. But prefer the Python approach since redis-cli may not be on PATH.

The result is the full `Cookie` header value. If empty/nil/None, tell the user: "No Forge session cookie found. Log in to Forge and make sure the cookie is stored in Redis."

## Step 5: Build the GraphQL payload

The executor definition JSON is ~1.2 MB, too large for shell command-line arguments. Use a Python heredoc to build the payload file (avoids `$` escaping issues):

```bash
python3 << 'PYEOF'
import json

with open('<WORKTREE>/_build/executor_definition.json') as f:
    definition = json.load(f)

query = 'mutation WorkflowRunnerButtonGroupLocal_CreateLocalBranchCloudRunMutation($input: CreateLocalBranchCloudRunInput!) { createLocalBranchCloudRun(input: $input) { id status workflow { name } } }'
payload = {
    'operationName': 'WorkflowRunnerButtonGroupLocal_CreateLocalBranchCloudRunMutation',
    'query': query,
    'variables': {
        'input': {
            'workflowId': 'wf_01jvn2wqkze4g8azbcn8nkb5rv',
            'status': 'queued',
            'definition': definition,
            'runPriority': 3,
            'functionName': '<ENTRY_POINT>',
            'functionType': 'fn',
            'runQueueId': 'runq_01k7qm57pmf53awpsbrcwnsr5b'
        }
    }
}

with open('/tmp/forge_payload.json', 'w') as f:
    json.dump(payload, f)
PYEOF
```

## Step 6: POST the GraphQL mutation and parse response

Save the response to a temp file (avoids stdin conflicts with heredocs), then parse it:

```bash
curl -s -X POST 'https://app.withforge.com/api/graphql/WorkflowRunnerButtonGroupLocal_CreateLocalBranchCloudRunMutation' \
  -H 'Content-Type: application/json' \
  -H "Cookie: <COOKIE_VALUE>" \
  -H "X-Request-ID: $(uuidgen)" \
  --data @/tmp/forge_payload.json \
  -o /tmp/forge_response.json
```

Then parse the response:

```bash
python3 -c "
import json, sys
with open('/tmp/forge_response.json') as f:
    data = json.load(f)
if 'errors' in data:
    print('ERROR:', data['errors'][0].get('message'))
    sys.exit(1)
if 'error' in data:
    print('ERROR:', data['error'])
    sys.exit(1)
run = data['data']['createLocalBranchCloudRun']
print(f'Forge run triggered: https://app.withforge.com/{run[\"id\"]}')
print(f'Status: {run[\"status\"]}')
print(f'Workflow: {run[\"workflow\"][\"name\"]}')
"
```

## Step 7: Cleanup

```bash
rm -f /tmp/forge_payload.json /tmp/forge_response.json
```
