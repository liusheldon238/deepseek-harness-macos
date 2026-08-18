window.__ModuleLoader__.load({
  id: "dsh-agent-preset-advisor",
  factory: (require) => {
    const module = { exports: {} };
    const React = require("react");
    const { createElement: h, useEffect, useMemo, useState } = React;

    const zh = {
      nav: "预设顾问",
      title: "Agent 预设顾问",
      intro: "把当前任务归类，再判断当前预设是否适合。分析在本机完成，不上传任务内容。",
      placeholder: "粘贴或输入当前要完成的任务…",
      analyze: "分析任务",
      analyzing: "正在分析…",
      summary: "任务摘要",
      current: "当前预设",
      recommendation: "推荐预设",
      suitable: "当前预设已适合这个任务",
      switchHint: "建议新建会话时使用该预设；正在运行的会话不会被切换。",
      setDefault: "设为新会话默认",
      defaulted: "已设为默认",
      noPresets: "没有可用的 Agent 预设。",
      loadError: "无法读取预设名单",
      overlay: "预设顾问",
      overlayHint: "分析输入框中的任务",
      empty: "先输入任务描述",
      kind: "任务类型"
    };
    const en = {
      nav: "Preset Advisor",
      title: "Agent Preset Advisor",
      intro: "Classify the task, then check whether the current preset is a good fit. Analysis stays local.",
      placeholder: "Paste or type the task you want to complete…",
      analyze: "Analyze task",
      analyzing: "Analyzing…",
      summary: "Task summary",
      current: "Current preset",
      recommendation: "Recommended preset",
      suitable: "The current preset fits this task",
      switchHint: "Use it when starting a new session; running sessions keep their preset.",
      setDefault: "Use for new sessions",
      defaulted: "Default updated",
      noPresets: "No Agent presets are available.",
      loadError: "Could not read the preset roster",
      overlay: "Preset advisor",
      overlayHint: "Analyze the composer task",
      empty: "Enter a task description first",
      kind: "Task type"
    };

    const BUILTIN = {
      standard: { zh: "标准模式", en: "Standard mode" },
      code: { zh: "PTC 模式", en: "PTC mode" },
      minimal: { zh: "极简模式", en: "Minimal mode" },
      cordis: { zh: "创造模式", en: "Creator mode" }
    };
    const RULES = [
      { id: "code", label: "编码 / Code", words: ["代码", "编程", "修复", "bug", "swift", "typescript", "javascript", "python", "api", "code", "debug", "编译", "测试"] },
      { id: "cordis", label: "插件与预设 / Plugin & preset", words: ["插件", "预设", "agent", "dsh", "cordis", "市场", "安装", "plugin", "preset"] },
      { id: "research", label: "研究与检索 / Research", words: ["研究", "调研", "搜索", "资料", "对比", "网页", "引用", "research", "search", "compare"] },
      { id: "writing", label: "写作与内容 / Writing", words: ["写作", "文章", "小说", "文案", "润色", "翻译", "总结", "写一篇", "write", "draft"] },
      { id: "data", label: "数据与文件 / Data", words: ["表格", "数据", "csv", "excel", "报表", "分析数据", "spreadsheet", "dataset"] }
    ];

    function textOf(preset, locale) {
      const built = BUILTIN[preset.id];
      return { name: built ? built[locale === "zh" ? "zh" : "en"] : (preset.name || preset.id), description: preset.description || "" };
    }
    function classify(input) {
      const value = input.toLowerCase();
      let best = { id: "general", label: "综合任务 / General", score: 0 };
      for (const rule of RULES) {
        const score = rule.words.reduce((sum, word) => sum + (value.includes(word.toLowerCase()) ? 1 : 0), 0);
        if (score > best.score) best = { id: rule.id, label: rule.label, score };
      }
      return best;
    }
    function recommend(kind, presets) {
      const healthy = presets.filter((p) => !p.broken);
      const preferred = kind.id === "cordis" ? ["cordis", "standard"] : kind.id === "code" ? ["code", "standard"] : kind.id === "writing" || kind.id === "research" || kind.id === "data" ? ["standard", "code"] : ["standard", "code", "minimal"];
      return preferred.map((id) => healthy.find((p) => p.id === id)).find(Boolean) || healthy[0];
    }
    function analyze(input, presets, locale, currentIdOverride) {
      const clean = input.trim().replace(/\s+/g, " ");
      const kind = classify(clean);
      const suggested = recommend(kind, presets);
      const current = (currentIdOverride && presets.find((p) => p.id === currentIdOverride)) || presets.find((p) => p.isDefault) || presets[0];
      if (!suggested || !current) return { kind, summary: clean.slice(0, 180), current: null, suggested: null, fit: true };
      return { kind, summary: clean.slice(0, 180), current: textOf(current, locale), suggested: textOf(suggested, locale), suggestedId: suggested.id, currentId: current.id, fit: suggested.id === current.id };
    }
    const card = { border: "1px solid var(--dsh-border, #d9dde5)", borderRadius: 12, padding: 14, background: "var(--dsh-surface, #fff)" };
    function AdvisorView({ api, t, locale, compact = false, initialTask = "", currentIdOverride }) {
      const [task, setTask] = useState(initialTask);
      const [presets, setPresets] = useState([]);
      const [result, setResult] = useState(null);
      const [error, setError] = useState("");
      const [saving, setSaving] = useState("");
      useEffect(() => { setTask(initialTask); }, [initialTask]);
      useEffect(() => { api.agentPresets.list({}).then((r) => r.result.ok ? setPresets(r.result.value.presets || []) : setError(r.result.error.message)).catch((e) => setError(String(e))); }, [api]);
      const run = () => { if (!task.trim()) { setError(t("empty")); return; } setError(""); setResult(analyze(task, presets, locale, currentIdOverride)); };
      const apply = async (id) => { setSaving(id); try { const r = await api.settings.update({ ns: "agent-presets", patch: { default: id } }); if (r.result.ok) { setPresets((all) => all.map((p) => ({ ...p, isDefault: p.id === id }))); setResult((old) => old ? { ...old, currentId: id, fit: true } : old); } else setError(r.result.error.message); } catch (e) { setError(String(e)); } finally { setSaving(""); } };
      return h("div", { "data-dsh-preset-advisor": "panel", style: { display: "grid", gap: 12, maxWidth: compact ? 520 : 760, padding: compact ? 8 : 18 } },
        !compact && h("div", null, h("h2", { style: { margin: "0 0 6px", fontSize: 20 } }, t("title")), h("p", { style: { margin: 0, opacity: .72 } }, t("intro"))),
        h("textarea", { value: task, onChange: (e) => setTask(e.target.value), placeholder: t("placeholder"), rows: compact ? 3 : 5, style: { width: "100%", resize: "vertical", boxSizing: "border-box", borderRadius: 9, border: "1px solid var(--dsh-border, #d9dde5)", padding: 10, font: "inherit" } }),
        h("button", { type: "button", onClick: run, style: { justifySelf: "start", border: 0, borderRadius: 8, padding: "8px 14px", background: "#1f6feb", color: "white", cursor: "pointer" } }, t("analyze")),
        error && h("div", { role: "alert", style: { color: "#b42318" } }, error),
        result && h("div", { style: { display: "grid", gap: 10 } },
          h("div", { style: card }, h("strong", null, t("summary")), h("p", { style: { margin: "7px 0 0" } }, result.summary)),
          h("div", { style: { display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: 10 } },
            h("div", { style: card }, h("strong", null, t("kind")), h("p", { style: { margin: "7px 0 0" } }, result.kind.label)),
            h("div", { style: card }, h("strong", null, t("current")), h("p", { style: { margin: "7px 0 0" } }, result.current ? result.current.name : t("noPresets"))),
            h("div", { style: { ...card, borderColor: result.fit ? "#12b76a" : "#f79009" } }, h("strong", null, result.fit ? t("suitable") : t("recommendation")), result.suggested && !result.fit && h("p", { style: { margin: "7px 0" } }, result.suggested.name), result.suggested && !result.fit && h("small", { style: { display: "block", opacity: .75 } }, t("switchHint")), result.suggested && !result.fit && h("button", { type: "button", onClick: () => apply(result.suggestedId), disabled: !!saving, style: { marginTop: 8, borderRadius: 7, border: "1px solid currentColor", padding: "6px 9px", background: "transparent", cursor: "pointer" } }, saving ? t("analyzing") : t("setDefault")), result.fit && h("p", { style: { margin: "7px 0 0", opacity: .75 } }, result.current?.description))
          )
        )
      );
    }
    function apply(ctx) {
      const api = ctx.get("connection").api;
      const locale = (ctx.locale?.current || "zh").startsWith("zh") ? "zh" : "en";
      ctx.effect(() => ctx.locale.register("settings.presetAdvisor", { zh, en }), "preset-advisor: locale");
      ctx.slots.inject("settings.section", () => ctx.slots.register({ name: "settings.section", id: "preset-advisor", order: 35, label: () => ctx.locale.bind("settings.presetAdvisor")(locale === "zh" ? "nav" : "nav"), locale: "settings.presetAdvisor", inject: () => ({ api, locale }) }, (props) => h(AdvisorView, { ...props, t: (key) => (props.t ? props.t(key) : (locale === "zh" ? zh[key] : en[key])), api, locale })));
      ctx.inject(["slots", "conversation"], (scope) => {
        function OverlayAdvisor({ api, locale, currentId }) {
          const [open, setOpen] = useState(false);
          const [draft, setDraft] = useState("");
          const copy = locale === "zh" ? zh : en;
          if (!open) return h("button", { type: "button", title: copy.overlayHint, onClick: () => { setDraft(document.querySelector("textarea")?.value || ""); setOpen(true); }, style: { border: "1px solid var(--dsh-border, #d9dde5)", borderRadius: 7, padding: "5px 8px", background: "transparent", cursor: "pointer", fontSize: 12 } }, copy.overlay);
          return h("div", { style: { border: "1px solid var(--dsh-border, #d9dde5)", borderRadius: 10, background: "var(--dsh-surface, #fff)", boxShadow: "0 8px 24px rgba(0,0,0,.12)" } }, h("button", { type: "button", onClick: () => setOpen(false), style: { float: "right", margin: 8, border: 0, background: "transparent", cursor: "pointer" } }, "×"), h(AdvisorView, { api, locale, compact: true, initialTask: draft, currentIdOverride: currentId, t: (key) => copy[key] }));
        }
        scope.slots.inject("conversation.input.overlay", () => scope.slots.register({ name: "conversation.input.overlay", id: "preset-advisor", order: 2, locale: "settings.presetAdvisor", inject: (sessionId) => ({ api, locale, currentId: scope.sessions.list.getSnapshot().byId[sessionId]?.agentPreset }) }, OverlayAdvisor));
      });
      ctx.effect(() => { const onAnalyze = (event) => { const task = event.detail || ""; if (!task.trim()) return; const panel = document.querySelector('[data-dsh-preset-advisor="panel"]'); if (panel) panel.scrollIntoView({ behavior: "smooth", block: "center" }); }; document.addEventListener("dsh-preset-advisor", onAnalyze); return () => document.removeEventListener("dsh-preset-advisor", onAnalyze); }, "preset-advisor: composer bridge");
    }
    module.exports = { apply, inject: ["@deepseek-ai/dsh-client-connection", "@deepseek-ai/dsh-client-locale", "@deepseek-ai/dsh-client-runtime", "@deepseek-ai/dsh-client-ui-conversation", "@deepseek-ai/dsh-client-ui-settings", "@deepseek-ai/dsh-api-remotes"] };
    return module.exports;
  }
});
