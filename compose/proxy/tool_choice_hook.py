# compose/proxy/tool_choice_hook.py
# LiteLLM pre-call hook: inject tool_choice=required only for execution requests.
#
# Problem: litellm_params.tool_choice="required" applies to ALL requests including
# OpenCode's Build/question step (which only has the "question" tool available).
# When the model is forced to call a tool but only "question" is in the schema,
# Qwen2.5-Coder generates a "write" tool call in its native <tool_call> XML format
# which llama.cpp cannot convert to structured tool_calls → outputs JSON as text →
# OpenCode's Build step ends without proceeding to execution.
#
# Fix: inject tool_choice=required only when the request contains execution tools
# (i.e., tools other than "question"). The Build/title steps are left untouched.

from litellm.integrations.custom_logger import CustomLogger


class ToolChoiceHook(CustomLogger):
    """Inject tool_choice=required for llama.cpp execution requests only."""

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        tools = data.get("tools") or []
        if not tools:
            # No tools in request (title generation step) — don't inject.
            return data

        tool_names = {t.get("function", {}).get("name", "") for t in tools}
        execution_tools = tool_names - {"question"}

        if execution_tools:
            # Has write/bash/read/etc. — force tool use so llama.cpp returns
            # structured tool_calls rather than <tool_call> XML as text.
            data["tool_choice"] = "required"
        # else: only "question" tool present (Build/plan step) — leave tool_choice
        # as-is (auto) so the model can use the question tool or return a text plan.

        return data

    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        return response

    async def async_post_call_failure_hook(
        self, request_data, original_exception, user_api_key_dict, **kwargs
    ):
        pass

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        pass

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        pass


proxy_handler_instance = ToolChoiceHook()
