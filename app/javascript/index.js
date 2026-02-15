import { createElement, useState, useEffect, useRef } from "react"
import { createRoot } from "react-dom/client"

function HomePage() {
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  const [sites, setSites] = useState([])
  const [loading, setLoading] = useState(true)
  const [expandedSiteId, setExpandedSiteId] = useState(null)
  const [runsBySiteId, setRunsBySiteId] = useState({})
  const [loadingRunsForId, setLoadingRunsForId] = useState(null)
  const [startingRunForId, setStartingRunForId] = useState(null)
  const [maxPages, setMaxPages] = useState(20)
  const [maxDepth, setMaxDepth] = useState(3)
  const [model, setModel] = useState("default")
  const cableRef = useRef(null)
  const subscriptionRef = useRef(null)

  useEffect(() => {
    fetch("/run_configs.json", {
      headers: { Accept: "application/json" },
    })
      .then((res) => res.ok ? res.json() : [])
      .then((data) => {
        const list = Array.isArray(data) ? data : []
        setSites(list)
        if (list.length > 0) setExpandedSiteId(list[0].id)
      })
      .catch(() => setSites([]))
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => {
    if (expandedSiteId == null || runsBySiteId[expandedSiteId] !== undefined) return
    setLoadingRunsForId(expandedSiteId)
    fetch(`/run_configs/${expandedSiteId}/runs.json`, { headers: { Accept: "application/json" } })
      .then((res) => (res.ok ? res.json() : []))
      .then((data) => {
        setRunsBySiteId((prev) => ({ ...prev, [expandedSiteId]: Array.isArray(data) ? data : [] }))
      })
      .catch(() => setRunsBySiteId((prev) => ({ ...prev, [expandedSiteId]: [] })))
      .finally(() => setLoadingRunsForId(null))
  }, [expandedSiteId])

  // Connect to Action Cable once on mount so the WebSocket is open before any subscription.
  useEffect(() => {
    const ActionCable = window.ActionCable
    if (!ActionCable?.createConsumer || cableRef.current) return
    const url = (window.location.protocol === "https:" ? "wss:" : "ws:") + "//" + window.location.host + "/cable"
    cableRef.current = ActionCable.createConsumer(url)
  }, [])

  useEffect(() => {
    if (expandedSiteId == null) {
      if (subscriptionRef.current) {
        subscriptionRef.current.unsubscribe()
        subscriptionRef.current = null
      }
      return
    }
    const siteId = Number(expandedSiteId)
    if (!siteId || !cableRef.current) return
    let cancelled = false
    try {
      const sub = cableRef.current.subscriptions.create(
        { channel: "RunConfigChannel", run_config_id: siteId },
        {
          received(data) {
            const run = data.run
            if (!run || !run.id) return
            console.log("[Cable] run update", run.id, run.status)
            const runConfigId = run.run_config_id
            // Prefer terminal states so out-of-order "running" doesn't overwrite "completed"/"failed"
            const terminal = (s) => s === "completed" || s === "failed"
            setRunsBySiteId((prev) => {
              const list = prev[runConfigId] || []
              const idx = list.findIndex((r) => r.id === run.id)
              const existing = idx >= 0 ? list[idx] : null
              const use = existing && terminal(existing.status) && !terminal(run.status) ? existing : run
              const next = idx >= 0 ? [...list.slice(0, idx), use, ...list.slice(idx + 1)] : [run, ...list]
              return { ...prev, [runConfigId]: next }
            })
          },
        }
      )
      subscriptionRef.current = sub
    } catch (e) {
      console.warn("[Cable] subscribe failed", e)
    }
    return () => {
      cancelled = true
      if (subscriptionRef.current) {
        subscriptionRef.current.unsubscribe()
        subscriptionRef.current = null
      }
    }
  }, [expandedSiteId])

  function startRun(siteId, e) {
    if (e) e.stopPropagation()
    if (startingRunForId != null) return
    setStartingRunForId(siteId)
    fetch(`/run_configs/${siteId}/runs`, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
      },
      body: JSON.stringify({ max_pages: maxPages, max_depth: maxDepth, model: model || null }),
    })
      .then((res) => {
        if (!res.ok) throw new Error("Failed to start run")
        return res.json()
      })
      .then((run) => {
        setRunsBySiteId((prev) => ({
          ...prev,
          [siteId]: [run, ...(prev[siteId] || [])],
        }))
      })
      .catch(() => {})
      .finally(() => setStartingRunForId(null))
  }

  function toggleSiteRuns(siteId) {
    if (expandedSiteId === siteId) {
      setExpandedSiteId(null)
      return
    }
    setExpandedSiteId(siteId)
    if (runsBySiteId[siteId] === undefined) {
      setLoadingRunsForId(siteId)
      fetch(`/run_configs/${siteId}/runs.json`, { headers: { Accept: "application/json" } })
        .then((res) => (res.ok ? res.json() : []))
        .then((data) => {
          setRunsBySiteId((prev) => ({ ...prev, [siteId]: Array.isArray(data) ? data : [] }))
        })
        .catch(() => setRunsBySiteId((prev) => ({ ...prev, [siteId]: [] })))
        .finally(() => setLoadingRunsForId(null))
    }
  }

  return createElement(
    "div",
    { className: "page-background" },
    createElement(
      "div",
      { className: "page-hero" },
      createElement("h1", { className: "page-title" }, "Generate llms.txt"),
      createElement(
        "div",
        { className: "prompt-box", "data-controller": "url-input" },
        createElement(
          "form",
          {
            className: "prompt-box-inner prompt-box--url",
            action: "/run_configs",
            method: "post",
            acceptCharset: "utf-8",
          },
          createElement("input", {
            type: "hidden",
            name: "authenticity_token",
            value: csrfToken,
          }),
          createElement(
            "div",
            { className: "prompt-box-url-row" },
            createElement("input", {
              id: "url",
              type: "text",
              name: "run_config[url]",
              placeholder: "tryprofound.com",
              autoComplete: "url",
              className: "prompt-input",
              "data-url-input-target": "input",
            })
          ),
          createElement(
            "div",
            { className: "prompt-box-options" },
            createElement(
              "label",
              { className: "prompt-option", htmlFor: "run-max-pages" },
              createElement("span", { className: "prompt-option-label" }, "Max pages"),
              createElement("input", {
                id: "run-max-pages",
                type: "number",
                className: "prompt-option-input",
                min: 1,
                max: 500,
                "aria-label": "Max pages to crawl",
                value: maxPages,
                onChange: (e) => {
                  const n = parseInt(e.target.value, 10)
                  if (!Number.isNaN(n) && n >= 1 && n <= 500) setMaxPages(n)
                },
              })
            ),
            createElement(
              "label",
              { className: "prompt-option", htmlFor: "run-max-depth" },
              createElement("span", { className: "prompt-option-label" }, "Max depth"),
              createElement("input", {
                id: "run-max-depth",
                type: "number",
                className: "prompt-option-input",
                min: 1,
                max: 10,
                "aria-label": "Max crawl depth",
                value: maxDepth,
                onChange: (e) => {
                  const n = parseInt(e.target.value, 10)
                  if (!Number.isNaN(n) && n >= 1 && n <= 10) setMaxDepth(n)
                },
              })
            ),
            createElement(
              "label",
              { className: "prompt-option" },
              createElement("span", { className: "prompt-option-label" }, "Model"),
              createElement(
                "select",
                {
                  className: "prompt-option-select",
                  value: model,
                  onChange: (e) => setModel(e.target.value),
                },
                createElement("option", { value: "default" }, "Default (All)"),
                createElement("option", { value: "opus-4.6" }, "Opus 4.6"),
                createElement("option", { value: "claude-3.5" }, "Claude 3.5"),
                createElement("option", { value: "gpt-4o" }, "GPT-4o"),
                createElement("option", { value: "none" }, "None")
              )
            ),
            createElement("button", {
              type: "submit",
              className: "prompt-submit-btn",
            }, "Generate")
          )
        )
      ),
      createElement(
        "div",
        { className: "run-configs-list-wrapper" },
        loading
          ? createElement("p", { className: "run-configs-list-message" }, "Loading…")
          : runConfigs.length === 0
            ? createElement("p", { className: "run-configs-list-message" }, "No run configs yet. Add one above.")
            : createElement(
                "ul",
                { className: "run-configs-list" },
                ...runConfigs.map((runConfig) => {
                  const isExpanded = expandedSiteId === runConfig.id
                  const runs = runsBySiteId[runConfig.id]
                  const loadingRuns = loadingRunsForId === runConfig.id
                  return createElement(
                    "li",
                    { key: runConfig.id, className: "run-configs-list-item" },
                    createElement(
                      "button",
                      {
                        type: "button",
                        className: "run-configs-list-site-row",
                        onClick: () => toggleSiteRuns(runConfig.id),
                      },
                      createElement("span", { className: "run-configs-list-site-expand" }, isExpanded ? "▼" : "▶"),
                      createElement("a", {
                        href: runConfig.url,
                        target: "_blank",
                        rel: "noopener noreferrer",
                        className: "run-configs-list-site-url",
                        onClick: (e) => e.stopPropagation(),
                      }, runConfig.url),
                      createElement("span", {
                        className: "run-configs-list-run-config",
                        "aria-label": "Run settings",
                      }, `${runConfig.maxPages} pages · ${runConfig.maxDepth} depth · ${runConfig.model || "Default"}`),
                      createElement("button", {
                        type: "button",
                        className: "run-configs-list-run-btn",
                        "aria-label": "Start run",
                        disabled: startingRunForId === runConfig.id,
                        onClick: (e) => startRun(runConfig.id, e),
                      }, startingRunForId === runConfig.id ? "…" : "Run")
                    ),
                    isExpanded &&
                      createElement(
                        "div",
                        { className: "run-configs-list-runs" },
                        loadingRuns
                          ? createElement("p", { className: "run-configs-list-runs-loading" }, "Loading runs…")
                          : !runs || runs.length === 0
                            ? createElement("p", { className: "run-configs-list-runs-empty" }, "No runs yet.")
                            : createElement(
                                "ul",
                                { className: "run-configs-list-runs-list" },
                                ...runs.map((run) =>
                                  createElement(
                                    "li",
                                    { key: run.id, className: "run-configs-list-run" },
                                    createElement("span", { className: "run-configs-list-run-status" }, run.status),
                                    run.started_at &&
                                      createElement("span", { className: "run-configs-list-run-time" },
                                        new Date(run.started_at).toLocaleString()),
                                    run.status === "completed" &&
                                      createElement("a", {
                                        href: `/runs/${run.id}/llms_txt`,
                                        target: "_blank",
                                        rel: "noopener noreferrer",
                                        className: "run-configs-list-run-view-btn",
                                        onClick: (e) => e.stopPropagation(),
                                      }, "View")
                                  )
                                )
                              )
                      )
                  )
                })
              )
      )
    )
  )
}

function mount() {
  const el = document.getElementById("root")
  if (el) {
    const root = createRoot(el)
    root.render(createElement(HomePage))
  }
}

document.addEventListener("turbo:load", mount)
