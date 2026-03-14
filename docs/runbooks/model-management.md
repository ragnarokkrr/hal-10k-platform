# Runbook: Ollama Model Management

**Stack**: `compose/ai/` (Ollama service)
**Model weights location**: `/srv/platform/models/`

---

## List Installed Models

```bash
docker exec ollama ollama list
```

Output columns: NAME · ID · SIZE · MODIFIED

---

## Pull a Model

```bash
# Pull by name:tag
docker exec ollama ollama pull <model>:<tag>

# Examples
docker exec ollama ollama pull qwen2.5-coder:32b
docker exec ollama ollama pull deepseek-r1:32b
docker exec ollama ollama pull llama3.3:70b
docker exec ollama ollama pull nomic-embed-text:latest   # for embeddings
```

Check available disk space before pulling large models:
```bash
df -h /srv/platform
```

---

## Remove a Model

```bash
docker exec ollama ollama rm <model>:<tag>

# Example
docker exec ollama ollama rm deepseek-r1:32b
```

Model weights are deleted from `/srv/platform/models/`. This is irreversible — you can
re-pull if needed.

---

## Show Model Info

```bash
docker exec ollama ollama show <model>:<tag>
```

---

## Add a New Model to LiteLLM Routing

After pulling a model in Ollama, register it in LiteLLM so API clients can use it:

### 1. Edit `compose/ai/litellm-config.yaml`

```yaml
model_list:
  # ... existing models ...

  - model_name: <friendly-name>      # used by API clients (e.g. "llama3.3:70b")
    litellm_params:
      model: ollama/<ollama-model-tag>  # must match `ollama list` NAME exactly
      api_base: http://ollama:11434
```

### 2. Restart LiteLLM

```bash
docker compose -f compose/ai/docker-compose.yml restart litellm
```

### 3. Verify the model appears

```bash
MASTER_KEY=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/ai.yaml | cut -d' ' -f2)
curl -sf -H "Authorization: Bearer ${MASTER_KEY}" \
  https://litellm.hal.local/models | python3 -m json.tool
```

---

## Initial Model Roster

| Model | Tag | Use Case | Approx. Size |
|-------|-----|----------|-------------|
| Qwen2.5-Coder | `32b` | Code generation, completion, review | ~20 GB |
| DeepSeek-R1 | `32b` | Reasoning, math, long-context analysis | ~20 GB |
| Llama 3.3 | `70b` | General purpose, instruction following | ~43 GB |

Pull order recommendation: start with `qwen2.5-coder:32b` (most frequently used),
then `deepseek-r1:32b`, then `llama3.3:70b` (largest — ensure disk space first).

---

## Run a Quick Inference Test

```bash
# Interactive
docker exec -it ollama ollama run qwen2.5-coder:32b

# Non-interactive (pipe a prompt)
echo "Write a bash one-liner to count lines in all .py files" \
  | docker exec -i ollama ollama run qwen2.5-coder:32b
```

> Use this to verify a model loaded correctly on the GPU before adding it to LiteLLM.

---

## Storage Layout

```
/srv/platform/models/
└── manifests/        # model metadata
└── blobs/            # model weight files (large)
```

This path is bind-mounted into the Ollama container at `/root/.ollama/models`.
Models survive container removal and image upgrades.
