Add test case(s) to a chime-disputes worktree's `src/testing/main_dev.sand` file.

Arguments: $ARGUMENTS (dispute IDs and optional flags, e.g. "19691736" or "19691736 19905222" or "19691736 --clear" or "67 --bug")

## Step 1: Parse arguments

Parse `$ARGUMENTS` for:
- **Dispute IDs**: numbers that are 7+ digits (e.g. `19691736`)
- **Bug number**: a 1-3 digit number, or `--bug <N>`, to specify the worktree
- **`--clear`**: if present, clear all existing test case rows before adding new ones

If no bug number is provided, extract it from the current working directory by looking for `bug-<N>` in the path.

If no bug number can be resolved, ask the user.

## Step 2: Resolve worktree path

```
WORKTREE=/Users/andrew/_dev/chime-disputes-worktrees/bug-<N>
```

Verify the directory exists. If not, tell the user and stop.

## Step 3: Look up run tags for each dispute ID

For each dispute ID, fetch the run tags from the Disputes API to get the inspector URL and dispute type.

Read the disputes cookie from Redis:
```bash
python3 -c "import redis; r = redis.Redis(host='localhost', port=6379, decode_responses=True); print(r.get('cookie:disputes_api'))"
```

If empty/None, tell the user: "No disputes API cookie found. Log in to https://oauth-disputes-dev.onrender.com in Chrome, then restart."

For each dispute ID, fetch:
```bash
curl -s 'https://oauth-disputes-dev.onrender.com/api/runs?limit=5&offset=0&sortBy=created_at&sortOrder=DESC&search=<DISPUTE_ID>' \
  -H 'accept: */*' \
  -H "cookie: <COOKIE>"
```

Parse the response to extract run tags:
```python
data = response_json
edges = data.get('data', {}).get('workflowRuns', {}).get('edges', [])
for edge in edges:
    tags = edge['node'].get('runTags', {})
    case_id = tags.get('case_id', '')
    inspector_url = tags.get('inspector_url', '')
    dispute_type = tags.get('dispute_type', '')
```

If no run is found for a dispute ID, tell the user and skip it.

Print each resolved test case:
```
Found: <CASE_ID> | <DISPUTE_TYPE> | <INSPECTOR_URL>
```

## Step 4: Read the current main_dev.sand

Read `<WORKTREE>/src/testing/main_dev.sand`.

Find the `rows: [` section inside the `run_test_cases_dev` function's `js_table` block.

## Step 5: Update the test cases

If `--clear` was specified, replace ALL existing rows with only the new test cases.

Otherwise, append the new test cases after the existing rows. Skip any dispute IDs that already appear in the rows.

Each row has the format:
```
      ["<CASE_ID>", "<INSPECTOR_URL>", "<DISPUTE_TYPE>"],
```

The last row should NOT have a trailing comma.

Use the Edit tool to update the file.

## Step 6: Confirm

Print a summary of what was done:
```
Updated <WORKTREE>/src/testing/main_dev.sand
Test cases:
  - <CASE_ID> (<DISPUTE_TYPE>)
  - ...
```

If `--clear` was used, note that previous test cases were cleared.
