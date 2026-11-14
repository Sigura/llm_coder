"""Builds calibration (imatrix) and test (KL divergence) text for a coding-agent model from local source code.

Each file becomes one agent episode in the Qwen3-Coder chat format: a user task, an XML tool call that reads the
file, the file as the tool response and a short assistant reply. Calibration and test come from disjoint sources.

Usage: python3 -I make_calib.py OUT_DIR
"""

import random
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
LLAMA_SRC = HOME / "llm_coder/llm/engines/.src/llama.cpp"
PYLIB = Path(sys.base_prefix) / f"lib/python{sys.version_info.major}.{sys.version_info.minor}"

CALIB_CHARS = 3_000_000
TEST_CHARS = 1_200_000
MAX_FILE_CHARS = 12_000

TASKS = [
    "Explain what {path} does and point out anything that looks like a bug.",
    "I need to change {path}. Read it first and summarize its structure.",
    "Review {path} for error handling problems.",
    "Find where the main logic of {path} lives and describe the control flow.",
]
REPLIES = [
    "I read `{path}`. Its main pieces are listed above; tell me which part to change and I will edit it.",
    "Done reading `{path}`. Nothing obviously broken; the error paths return early and the state is local.",
    "`{path}` is self-contained. The next step is to run its tests before changing anything.",
]
SYSTEM = ("You are a coding agent working in a local repository. Use the tools to read files before answering. "
          "Tools: read_file(path), list_dir(path), run(command).")


def git_files(repo, prefixes, suffixes):
    out = subprocess.run(["git", "-C", str(repo), "ls-tree", "-r", "--name-only", "HEAD", *prefixes],
                         check=True, capture_output=True, text=True).stdout.split()
    for name in out:
        if name.endswith(suffixes):
            text = subprocess.run(["git", "-C", str(repo), "show", f"HEAD:{name}"], capture_output=True).stdout
            yield f"llama.cpp/{name}", text.decode("utf-8", "replace")


def tree_files(root, label, suffixes):
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.suffix in suffixes and "__pycache__" not in p.parts and "/test" not in str(p):
            yield f"{label}/{p.relative_to(root)}", p.read_text(errors="replace")


def episode(rng, path, text):
    text = text[:MAX_FILE_CHARS]
    task = rng.choice(TASKS).format(path=path)
    reply = rng.choice(REPLIES).format(path=path)
    return (f"<|im_start|>system\n{SYSTEM}<|im_end|>\n"
            f"<|im_start|>user\n{task}<|im_end|>\n"
            f"<|im_start|>assistant\n<tool_call>\n<function=read_file>\n<parameter=path>\n{path}\n</parameter>\n"
            f"</function>\n</tool_call><|im_end|>\n"
            f"<|im_start|>user\n<tool_response>\n{text}\n</tool_response><|im_end|>\n"
            f"<|im_start|>assistant\n{reply}<|im_end|>\n")


def build(sources, limit, rng):
    files = [f for src in sources for f in src if len(f[1]) > 400]
    rng.shuffle(files)
    out, size = [], 0
    for path, text in files:
        e = episode(rng, path, text)
        out.append(e)
        size += len(e)
        if size >= limit:
            break
    return "".join(out), len(out)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0)
    calib = [
        git_files(LLAMA_SRC, ["src", "ggml/src/ggml-cuda", "common", "tools/server"], (".cpp", ".h", ".cu", ".cuh")),
        git_files(LLAMA_SRC, ["gguf-py", "convert_hf_to_gguf.py"], (".py",)),
        tree_files(PYLIB / "asyncio", "cpython/asyncio", {".py"}),
        tree_files(PYLIB / "json", "cpython/json", {".py"}),
        tree_files(PYLIB / "email", "cpython/email", {".py"}),
    ]
    site = PYLIB / "site-packages"
    test = [
        tree_files(site / "huggingface_hub", "huggingface_hub", {".py"}),
        tree_files(site / "numpy/_core", "numpy/_core", {".py"}),
        tree_files(HOME / "llm_coder/stack/scripts", "stack/scripts", {".sh", ".py"}),
        tree_files(HOME / "burnish/src", "burnish/src", {".py"}),
    ]
    for name, sources, limit in [("calib", calib, CALIB_CHARS), ("test", test, TEST_CHARS)]:
        text, n = build(sources, limit, rng)
        (out / f"{name}.txt").write_text(text)
        print(f"{name}: {n} episodes, {len(text) / 1e6:.2f} M chars")


if __name__ == "__main__":
    main()
