# Independent review

After you write or change code, and before you report the task as done, get an independent review:

```
~/llm_coder/stack/scripts/llm-review.sh --task "<what the code must do, one or two sentences>" <changed files>
```

Add `--diff` instead of (or as well as) the file list when the project is a git repository. The reviewer (Qwen3.6 MTP,
a different model from the one that wrote the code) only sees the task and the code, not this conversation. It
answers `OK` or one line per defect (`path:line: problem -> fix`). Fix the defects you agree with, then run it once
more. Stop after two rounds. Tell the user which findings you did not fix and why. Review once per finished change,
not after every edit.
