# ADR-0013: LiteLLM Pre-Call Hook for Conditional tool_choice Injection

**Date**: 2026-03-17
**Status**: Accepted

Supersedes: nothing — extends ADR-0011 (llama.cpp function-calling stack)

---

## Context

ADR-0011 established `compose/ai-tools/` (llama.cpp) as the function-calling backend
and `compose/proxy/` (LiteLLM) as the API gateway. After that architecture was deployed,
end-to-end testing of OpenCode agentic sessions revealed that tool calls were never
executed — the model output appeared as raw JSON text in the UI and no files were written.

Root-cause analysis required tracing the request path across three layers:
OpenCode → LiteLLM → llama.cpp.

---

## The Three Bugs

### Bug 1 — llama.cpp Jinja Streaming: tool_calls not populated without tool_choice (Upstream, Not Yet Fixed)

llama.cpp with `--jinja` uses the GGUF-embedded Jinja2 chat template to format requests
and parse responses. For Qwen2.5-Coder, that template generates tool calls wrapped in
`<tool_call>` XML:

```
<tool_call>{"name": "write", "arguments": {...}}</tool_call>
```

**In non-streaming mode**, llama.cpp correctly converts this into an OpenAI `tool_calls`
array with `finish_reason: tool_calls`.

**In streaming mode** (the only mode OpenCode uses), llama.cpp fails to convert the
`<tool_call>` tokens into `tool_calls` chunks when `tool_choice` is absent or `"auto"`.
Instead, the JSON leaks out as plain `content` text with `finish_reason: stop`.

Confirmed behaviour matrix:

| Mode | tool_choice | Result |
|------|-------------|--------|
| Non-streaming | any | ✓ `tool_calls` populated |
| Streaming | `"required"` | ✓ `tool_calls` populated |
| Streaming | `"auto"` | ✗ JSON leaks as `content` text |
| Streaming | absent | ✗ JSON leaks as `content` text |

**This is a llama.cpp upstream bug** (build b8390, `ghcr.io/ggml-org/llama.cpp:server-rocm`,
the latest available image at time of writing). Monitor future container releases and
remove the `tool_choice: "required"` injection from `tool_choice_hook.py` once this is
fixed. The non-streaming path can serve as a smoke-test to confirm the fix: if streaming
returns `tool_calls` without `tool_choice: "required"`, the bug is resolved.

**Monitoring**: after any llama.cpp image upgrade, run:

```bash
# Streaming without tool_choice — if this returns finish_reason: tool_calls, bug is fixed
docker exec litellm python3 -c "
import urllib.request, json
data = {
  'model': 'qwen2.5-coder:32b',
  'messages': [{'role': 'user', 'content': 'write hi to /tmp/t.html'}],
  'tools': [{'type': 'function', 'function': {'name': 'write',
    'parameters': {'type': 'object',
      'properties': {'filePath': {'type': 'string'}, 'content': {'type': 'string'}},
      'required': ['filePath', 'content']}}}],
  'stream': True, 'max_tokens': 100
}
req = urllib.request.Request('http://llama-cpp-qwen32b:8080/v1/chat/completions',
  data=json.dumps(data).encode(), headers={'Content-Type': 'application/json'})
with urllib.request.urlopen(req, timeout=30) as r:
  body = r.read().decode()
if 'tool_calls' in body and '\"finish_reason\":\"tool_calls\"' in body:
  print('BUG FIXED — streaming tool_calls works without tool_choice')
else:
  print('Bug still present — keep tool_choice_hook.py')
"
```

### Bug 2 — OpenCode Build Step: wrong tool_choice injection scope

OpenCode's agentic session has two distinct request phases:

| Phase | Tools sent | OpenCode's tool_choice | Purpose |
|-------|-----------|------------------------|---------|
| Build / plan | `[question]` only | `"auto"` | Clarify the task or generate a plan |
| Execute | `[write, bash, read, glob, grep, edit, ...]` | `"auto"` | Execute tools to complete the task |

The naive fix for Bug 1 — setting `tool_choice: "required"` in `litellm_params` for all
requests to the `-tools` model aliases — broke the Build phase:

1. LiteLLM injects `tool_choice: "required"` regardless of which tools are in the request
2. Build phase arrives with only `[question]` in the tools list
3. Qwen2.5-Coder, forced to call a tool, prefers to call `write` directly (the task is clear)
4. `write` is not in the Build phase's schema → llama.cpp cannot parse it into `tool_calls`
5. The `write` JSON leaks as `content` text (Bug 1 reprises on the wrong request)
6. OpenCode displays the JSON string, considers the Build complete, and **never starts the Execute phase**

### Bug 3 — LiteLLM model database: tools parameter dropped by drop_params

LiteLLM's `drop_params: true` (required to strip the Anthropic `thinking` parameter for
Ollama models — see ADR-0011) calls `supports_function_calling()` to decide whether to
pass the `tools` parameter to the backend:

```python
litellm.supports_function_calling(model='openai/qwen2.5-coder:32b')
# → False
```

`qwen2.5-coder:32b` is not in LiteLLM's model capability database as a function-calling
model. As a result, `drop_params: true` strips the `tools` array before it reaches
llama.cpp — even though llama.cpp is fully capable of handling it.

Note: `get_supported_openai_params()` for `openai/` prefix models does include `tools` in
the returned list, creating an apparent contradiction. `drop_params` uses the
`supports_function_calling()` check, not the params list.

---

## Decision

### Solution: LiteLLM Pre-Call Hook (`tool_choice_hook.py`)

A Python hook registered in `litellm_settings.callbacks` conditionally injects
`tool_choice: "required"` only when the request contains execution tools (anything
other than `question`). The `litellm_params.tool_choice` static setting is removed
from the `-tools` model entries.

**Hook logic** (`compose/proxy/tool_choice_hook.py`):

```python
async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
    tools = data.get("tools") or []
    tool_names = {t.get("function", {}).get("name", "") for t in tools}
    execution_tools = tool_names - {"question"}

    if execution_tools:
        data["tool_choice"] = "required"   # Execute phase — inject
    # else: Build/title phase — leave as-is (auto)
    return data
```

**Registration** (`compose/proxy/litellm-config.yaml`):

```yaml
litellm_settings:
  drop_params: true
  callbacks: ["tool_choice_hook.proxy_handler_instance"]
```

**Volume mount** (`compose/proxy/docker-compose.yml`):

```yaml
volumes:
  - ./litellm-config.yaml:/app/config.yaml:ro
  - ./tool_choice_hook.py:/app/tool_choice_hook.py:ro
```

LiteLLM's `get_instance_fn()` resolves `"tool_choice_hook.proxy_handler_instance"` by:
1. Splitting on the last `.` → module=`tool_choice_hook`, instance=`proxy_handler_instance`
2. Loading `/app/tool_choice_hook.py` (relative to the config file at `/app/config.yaml`)
3. Returning `proxy_handler_instance` from the module

**Fix for Bug 3** (`model_info` in each `-tools` entry):

```yaml
model_info:
  supports_function_calling: true
```

This overrides LiteLLM's model DB entry and prevents `drop_params` from stripping the
`tools` parameter for the `-tools` model aliases.

---

## Request Flow After Fix

```
OpenCode Build phase (question tool only, tool_choice: auto)
  → LiteLLM receives request
  → hook: tool_names = {"question"}, execution_tools = {} → no injection
  → llama.cpp receives: tools=[question], tool_choice: auto
  → model returns text plan or question tool call
  → Build phase completes normally

OpenCode Execute phase (all tools, tool_choice: auto)
  → LiteLLM receives request
  → hook: execution_tools = {"write", "bash", ...} → injects tool_choice: "required"
  → llama.cpp receives: tools=[write, bash, ...], tool_choice: "required"
  → streaming returns proper tool_calls chunks, finish_reason: tool_calls
  → OpenCode executes the tool (file written, bash run, etc.)
```

---

## Verification

```bash
# Build phase (question only) — must NOT get tool_choice: required
# Expected: finish_reason: length or stop, no tool_calls
curl -sk https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder:32b-tools",
    "messages": [{"role": "user", "content": "create test.html"}],
    "tools": [{"type": "function", "function": {"name": "question",
      "parameters": {"type": "object", "properties": {"q": {"type": "string"}}}}}],
    "max_tokens": 50, "stream": false
  }' | python3 -c "import sys,json; c=json.load(sys.stdin)['choices'][0];
     print('finish_reason:', c['finish_reason']);
     print('tool_calls:', bool(c['message'].get('tool_calls')))"

# Execute phase (write tool present) — must get tool_choice: required injected
# Expected: finish_reason: tool_calls, tool_name: write
curl -sk https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder:32b-tools",
    "messages": [{"role": "user", "content": "write hi to /tmp/test.html"}],
    "tools": [
      {"type": "function", "function": {"name": "question",
        "parameters": {"type": "object", "properties": {"q": {"type": "string"}}}}},
      {"type": "function", "function": {"name": "write",
        "parameters": {"type": "object",
          "properties": {"filePath": {"type": "string"}, "content": {"type": "string"}},
          "required": ["filePath", "content"]}}}
    ],
    "max_tokens": 100, "stream": false
  }' | python3 -c "import sys,json; c=json.load(sys.stdin)['choices'][0];
     tc=c['message'].get('tool_calls');
     print('finish_reason:', c['finish_reason']);
     print('tool_name:', tc[0]['function']['name'] if tc else 'none')"

# End-to-end: OpenCode writes a file
export NODE_EXTRA_CA_CERTS=/srv/platform/secrets/hal-local.crt
export LITELLM_API_KEY=<LITELLM_MASTER_KEY>
opencode --model hal/qwen2.5-coder:32b-tools
# Prompt: "create a hello world test.html in /tmp"
cat /tmp/test.html   # file must exist with HTML content
```

---

## Consequences

**Positive**
- OpenCode agentic tool execution works end-to-end: file writes, bash runs, codebase edits
- Build phase behaves correctly: model can ask clarifying questions or return a text plan
- Hook is scoped to the pre-call path only; no impact on Ollama routes or non-tools models
- Minimal code: 50 lines of Python, no external dependencies

**Negative**
- Additional moving part in the LiteLLM config (volume mount + callback registration)
- Hook must be updated if OpenCode adds new non-execution tools that should not trigger `tool_choice: required`
- Dependency on the llama.cpp streaming bug remaining present — if it is fixed upstream, the hook becomes unnecessary overhead (harmless but should be removed)

**Neutral**
- `tool_choice_hook.py` is version-controlled alongside `litellm-config.yaml` in `compose/proxy/`
- The hook applies to all three `-tools` model aliases (qwen32b, deepseek32b, llama70b)

---

## Future Work

| Item | Trigger |
|------|---------|
| Remove `tool_choice: "required"` injection from hook | llama.cpp streaming bug fixed (use monitoring script above) |
| Expand hook to inject other per-request parameters | New model backends with non-standard requirements |
| Remove `model_info: supports_function_calling: true` overrides | LiteLLM model DB updated for these models |
