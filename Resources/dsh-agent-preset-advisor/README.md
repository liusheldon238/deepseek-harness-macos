# dsh-agent-preset-advisor

The preset advisor is a client-only DeepSeek Harness plugin. It adds a Preset Advisor settings page and a button in the conversation composer.

It reads the available preset roster and analyzes the task text locally with transparent keyword rules. It can mark the current/default preset as a fit or recommend another preset for the next session. Choosing a recommendation updates the `agent-presets` default; an already-running session is never changed.

Task text is not sent to a server by this plugin.
