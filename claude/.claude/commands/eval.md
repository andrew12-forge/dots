Run an LLM eval from a downloaded eval log file.

Arguments: $ARGUMENTS (space-separated)
- First arg (required): path to the eval log JSON file (e.g. `~/Downloads/model_eval_log-xxx.json`)
- Iteration count: any of these forms — `-n 1000`, `n=1000`, `n == 1000`, `n 1000`, or just a bare number like `1000`. Default: 100.
- `--only <key1,key2,...>`: only assert on these output keys (strips other keys from expected output). If omitted, asserts on the full output exactly.
- `-m <model>`: override the LLM model
- `-p <count>`: parallelism (default: 20)

Examples:
- `/eval ~/Downloads/model_eval_log-xxx.json n=1000 --only scenario_number`
- `/eval ~/Downloads/model_eval_log-xxx.json n == 500 --only scenario_number,next_step`
- `/eval ~/Downloads/model_eval_log-xxx.json -n 200 -m claude-sonnet-4`
- `/eval ~/Downloads/model_eval_log-xxx.json 300` → n=300, full exact match
- `/eval ~/Downloads/model_eval_log-xxx.json` → n=100, full exact match

## Step 1: Parse arguments

Split `$ARGUMENTS` on whitespace. Extract:
- The eval log path: the first token that looks like a file path (contains `/` or ends in `.json`)
- Iteration count: look for any of these patterns and extract the number:
  - `-n <number>`
  - `n=<number>` or `n =<number>` or `n= <number>` or `n = <number>`
  - `n==<number>` or `n == <number>` (with any spacing around `==`)
  - `n <number>`
  - A bare number token (not associated with another flag like `-p` or `-m`)
  - Default to 100 if not specified
- `--only <keys>`: comma-separated list of output keys to assert on. Optional.
- `-m <model>`: model override. Optional.
- `-p <count>`: parallelism override. Optional.

If no file path is found, ask the user for the eval log path.

Resolve `~` to the user's home directory. Verify the file exists by reading it.

## Step 2: Read and prepare the eval log

Read the eval log JSON file. Parse the `outputs.output` field (it's a JSON string).

Display to the user:
- The `functionName`
- A brief summary of the inputs (first ~100 chars of the objective, and the input variable names)
- The expected output (parsed)
- The `-n` count and any `--only` filter

## Step 3: Apply --only filter (if specified)

If `--only` is provided, parse the `outputs.output` JSON string, keep only the specified keys, and re-serialize it back. This enables partial assertions — the eval runner will only compare the keys present in the expected output.

For example, if `--only scenario_number` is specified and the output is:
```json
{"scenario_number":"1","justification":"...long text..."}
```
It becomes:
```json
{"scenario_number":"1"}
```

## Step 4: Copy to cases directory

Copy the (potentially modified) eval log to the monorepo cases directory:

```
MONOREPO=/Users/andrew/_dev/monorepo
DEST=$MONOREPO/api/llmEval/cases/gen_output/<original_filename>.json
```

If using `--only`, write the modified JSON to the destination. Otherwise, copy the original file as-is.

## Step 5: Run the eval

Build and run the eval command from the monorepo root:

```bash
cd /Users/andrew/_dev/monorepo && yarn eval:llm run --clear-logs -c "gen_output/<filename>.json" -n <count> [-m <model>] [-p <parallelism>]
```

Run this in the background with a 10-minute timeout so we can continue chatting.

## Step 6: Report results

When the eval completes, read the output and report:
- Pass/fail ratio (e.g. 998/1000)
- Mean, median, and P95 latency
- If there were failures, show a sample of the failure reasons
