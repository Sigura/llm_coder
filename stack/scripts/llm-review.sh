#!/usr/bin/env bash
# Usage: llm-review.sh [--model <model-id>] [--diff] --task "<what the code must do>" [file...]
# Independent code review outside the agent's context: sends only a short reviewer prompt, the task and the given
# files (and/or `git diff HEAD` with --diff) to a local model (default Qwen3.6 MTP on 8085, thinking off) and prints
# its verdict: "OK" or at most 10 lines "path:line: problem -> fix". On the coding eval a reviewer added ~4-5 tasks to
# Qwen3.8, and Qwen3.6 MTP did as well as DeepSeek at ~60% of the time; --model deepseek-v4.1-flash-1017 for DeepSeek.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd curl jq
load_global

MODEL=qwen3.6-35b-a3b-mtp TASK="" DIFF=0
while (($#)); do
    case $1 in
    --model) MODEL=$2; shift ;;
    --task) TASK=$2; shift ;;
    --diff) DIFF=1 ;;
    -h | --help) sed -n '2,6p' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) break ;;
    esac
    shift
done
[[ -n $TASK ]] || die "--task is required: say what the code must do"
(($# || DIFF)) || die "give files to review and/or --diff"
load_model "$MODEL"

code=""
for f in "$@"; do
    [[ -f $f ]] || die "not a file: $f"
    code+="=== $f"$'\n'"$(cat -n "$f")"$'\n'
done
if ((DIFF)); then
    code+="=== git diff HEAD"$'\n'"$(git diff HEAD)"$'\n'
fi

system='You are a strict code reviewer. You get a task description and code written by another model.
Find real defects only: wrong behavior versus the task, crashes, unhandled edge cases the task implies, security
problems, broken commands. Ignore style, naming and missing comments.
Answer in at most 10 lines and nothing else: either the single word OK, or one line per defect in the form
path:line: problem -> fix'
body=$(jq -n --arg sys "$system" --arg user "Task: $TASK"$'\n\n'"$code" --arg model "$ALIAS" \
    '{model: $model, messages: [{role: "system", content: $sys}, {role: "user", content: $user}],
      max_tokens: 600, temperature: 0.2, chat_template_kwargs: {enable_thinking: false}}')
API_KEY=$(api_key)
printf '%s' "$body" | curl -sS --fail-with-body --max-time 1800 "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' --data-binary @- |
    jq -r '.choices[0].message.content // error("no reply: \(.)")'
