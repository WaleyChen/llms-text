import { createElement, useState, useEffect, useRef } from "react"
import { createRoot } from "react-dom/client"

function HomePage() {
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  const [runConfigs, setRunConfigs] = useState([])
  const [loading, setLoading] = useState(true)
  const [expandedSiteIds, setExpandedSiteIds] = useState(() => new Set())
  const [runsBySiteId, setRunsBySiteId] = useState({})
  const [loadingRunsForIds, setLoadingRunsForIds] = useState(() => new Set())
  const [maxPages, setMaxPages] = useState(20)
  const [maxDepth, setMaxDepth] = useState(3)
  const [model, setModel] = useState("all")
  const cableRef = useRef(null)
  const subscriptionsRef = useRef({})

  useEffect(() => {
    fetch("/run_configs.json", {
      headers: { Accept: "application/json" },
    })
      .then((res) => res.ok ? res.json() : [])
      .then((data) => {
        const list = Array.isArray(data) ? data : []
        setRunConfigs(list)
        if (list.length > 0) setExpandedSiteIds((prev) => new Set([...prev, list[0].id]))
      })
      .catch(() => setRunConfigs([]))
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => {
    const toFetch = [...expandedSiteIds].filter((id) => runsBySiteId[id] === undefined && !loadingRunsForIds.has(id))
    if (toFetch.length === 0) return
    setLoadingRunsForIds((prev) => new Set([...prev, ...toFetch]))
    toFetch.forEach((siteId) => {
      fetch(`/run_configs/${siteId}/runs.json`, { headers: { Accept: "application/json" } })
        .then((res) => (res.ok ? res.json() : []))
        .then((data) => {
          setRunsBySiteId((prev) => ({ ...prev, [siteId]: Array.isArray(data) ? data : [] }))
        })
        .catch(() => setRunsBySiteId((prev) => ({ ...prev, [siteId]: [] })))
        .finally(() => setLoadingRunsForIds((prev) => {
          const next = new Set(prev)
          next.delete(siteId)
          return next
        }))
    })
  }, [expandedSiteIds])

  // Connect to Action Cable once on mount so the WebSocket is open before any subscription.
  useEffect(() => {
    const ActionCable = window.ActionCable
    if (!ActionCable?.createConsumer || cableRef.current) return
    const url = (window.location.protocol === "https:" ? "wss:" : "ws:") + "//" + window.location.host + "/cable"
    cableRef.current = ActionCable.createConsumer(url)
  }, [])

  useEffect(() => {
    if (!cableRef.current) return
    const ids = [...expandedSiteIds].map(Number).filter(Boolean)
    const subs = subscriptionsRef.current
    ids.forEach((siteId) => {
      if (subs[siteId]) return
      try {
        subs[siteId] = cableRef.current.subscriptions.create(
          { channel: "RunConfigChannel", run_config_id: siteId },
          {
            received(data) {
              const run = data.run
              if (!run || !run.id) return
              console.log("[Cable] run update", run.id, run.status)
              const runConfigId = run.run_config_id
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
      } catch (e) {
        console.warn("[Cable] subscribe failed for", siteId, e)
      }
    })
    Object.keys(subs).forEach((key) => {
      const id = Number(key)
      if (!expandedSiteIds.has(id)) {
        subs[id]?.unsubscribe()
        delete subs[id]
      }
    })
  }, [expandedSiteIds])

  function formatDuration(startedAt, finishedAt) {
    if (!startedAt || !finishedAt) return null
    const ms = new Date(finishedAt) - new Date(startedAt)
    if (ms < 0) return null
    if (ms < 1000) return `${Math.round(ms)}ms`
    const sec = ms / 1000
    if (sec < 60) return `${sec.toFixed(1)}s`
    const min = Math.floor(sec / 60)
    const s = sec % 60
    return s >= 0.05 ? `${min}m ${s.toFixed(1)}s` : `${min}m`
  }

  function toggleSiteRuns(siteId) {
    setExpandedSiteIds((prev) => {
      const next = new Set(prev)
      if (next.has(siteId)) {
        next.delete(siteId)
      } else {
        next.add(siteId)
      }
      return next
    })
  }

  function fillUrlInput(url) {
    const input = document.getElementById("url")
    if (input) {
      input.value = url
      input.focus()
    }
  }

  function useUrlIcon(url) {
    return createElement(
      "button",
      {
        type: "button",
        className: "run-configs-list-use-url-btn",
        "aria-label": "Use this URL in the form",
        title: "Use this URL",
        onClick: (e) => {
          e.stopPropagation()
          fillUrlInput(url)
        },
      },
      createElement(
        "svg",
        {
          width: 14,
          height: 14,
          viewBox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          strokeWidth: 2,
          strokeLinecap: "round",
          strokeLinejoin: "round",
          "aria-hidden": true,
        },
        createElement("path", { d: "M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" }),
        createElement("rect", { x: "8", y: "2", width: "8", height: "4", rx: "1", ry: "1" })
      )
    )
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
            async onSubmit(e) {
              e.preventDefault()
              const form = e.target
              const url = form.querySelector('input[name="run_config[url]"]')?.value?.trim() || ""
              const payload = {
                run_config: {
                  url,
                  max_pages: maxPages === "" ? null : Number(maxPages),
                  max_depth: maxDepth === "" ? null : Number(maxDepth),
                  model: model || "all",
                },
              }
              try {
                const res = await fetch("/run_configs", {
                  method: "POST",
                  headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": csrfToken,
                  },
                  body: JSON.stringify(payload),
                })
                const data = await res.json().catch(() => ({}))
                if (res.ok) {
                  const runConfig = data.run_config
                  const runs = data.runs || (data.run ? [data.run] : [])
                  if (runConfig) {
                    setRunConfigs((prev) => [runConfig, ...prev])
                    if (runs.length > 0) {
                      setRunsBySiteId((prev) => ({
                        ...prev,
                        [runConfig.id]: [...runs, ...(prev[runConfig.id] || [])],
                      }))
                    }
                    setExpandedSiteIds((prev) => new Set([...prev, runConfig.id]))
                  }
                } else {
                  const msg = data.errors?.join?.(" ") || "Failed to add run config"
                  alert(msg)
                }
              } catch (err) {
                alert("Failed to add run config")
              }
            },
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
              createElement("span", { className: "prompt-option-label" }, "Max Pages"),
              createElement("input", {
                id: "run-max-pages",
                type: "number",
                name: "run_config[max_pages]",
                className: "prompt-option-input",
                min: 1,
                max: 999,
                "aria-label": "Max pages to crawl",
                value: maxPages === "" ? "" : maxPages,
                onChange: (e) => {
                  const v = e.target.value
                  if (v === "") setMaxPages("")
                  else {
                    const n = parseInt(v, 10)
                    if (!Number.isNaN(n) && n >= 1 && n <= 999) setMaxPages(n)
                  }
                },
              })
            ),
            createElement(
              "label",
              { className: "prompt-option", htmlFor: "run-max-depth" },
              createElement("span", { className: "prompt-option-label" }, "Max Depth"),
              createElement("input", {
                id: "run-max-depth",
                type: "number",
                name: "run_config[max_depth]",
                className: "prompt-option-input",
                min: 1,
                max: 10,
                "aria-label": "Max crawl depth",
                value: maxDepth === "" ? "" : maxDepth,
                onChange: (e) => {
                  const v = e.target.value
                  if (v === "") setMaxDepth("")
                  else {
                    const n = parseInt(v, 10)
                    if (!Number.isNaN(n) && n >= 1 && n <= 10) setMaxDepth(n)
                  }
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
                  name: "run_config[model]",
                  className: "prompt-option-select",
                  value: model,
                  onChange: (e) => setModel(e.target.value),
                },
                createElement("option", { value: "all" }, "Default (All)"),
                createElement("option", { value: "claude-sonnet-4-5" }, "Claude Sonnet 4.5"),
                createElement("option", { value: "gpt-5.2-mini" }, "GPT-5.2 Mini"),
                createElement("option", { value: "N/A" }, "None")
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
                  const isExpanded = expandedSiteIds.has(runConfig.id)
                  const runs = runsBySiteId[runConfig.id]
                  const loadingRuns = loadingRunsForIds.has(runConfig.id)
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
                      createElement(
                        "span",
                        { className: "run-configs-list-site-url-wrap" },
                        createElement("a", {
                          href: runConfig.url,
                          target: "_blank",
                          rel: "noopener noreferrer",
                          className: "run-configs-list-site-url",
                          onClick: (e) => e.stopPropagation(),
                        }, runConfig.url),
                        useUrlIcon(runConfig.url)
                      ),
                      createElement("span", {
                        className: "run-configs-list-run-config",
                        "aria-label": "Run settings",
                      }, `${runConfig.max_pages} pages · ${runConfig.max_depth} depth · ${runConfig.model || "Default"}`)
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
                                "div",
                                { className: "run-configs-list-runs-table" },
                                createElement(
                                  "div",
                                  { className: "run-configs-list-runs-header" },
                                  createElement("span", { className: "run-configs-list-run-status" }, "Status"),
                                  createElement("span", { className: "run-configs-list-run-time" }, "Started"),
                                  createElement("span", { className: "run-configs-list-run-finished" }, "Finished"),
                                  createElement("span", { className: "run-configs-list-run-duration" }, "Duration"),
                                  createElement("span", { className: "run-configs-list-run-model" }, "Model"),
                                  createElement("span", { className: "run-configs-list-run-action" })
                                ),
                                createElement(
                                  "ul",
                                  { className: "run-configs-list-runs-list" },
                                  ...runs.map((run) =>
                                    createElement(
                                      "li",
                                      { key: run.id, className: "run-configs-list-run" },
                                      createElement("span", { className: "run-configs-list-run-status" }, run.status),
                                      run.started_at
                                        ? createElement("span", { className: "run-configs-list-run-time" }, new Date(run.started_at).toLocaleString())
                                        : createElement("span", { className: "run-configs-list-run-time" }, "—"),
                                      run.finished_at
                                        ? createElement("span", { className: "run-configs-list-run-finished" }, new Date(run.finished_at).toLocaleString())
                                        : createElement("span", { className: "run-configs-list-run-finished" }, "—"),
                                      formatDuration(run.started_at, run.finished_at)
                                        ? createElement("span", { className: "run-configs-list-run-duration" }, formatDuration(run.started_at, run.finished_at))
                                        : createElement("span", { className: "run-configs-list-run-duration" }, "—"),
                                      createElement("span", { className: "run-configs-list-run-model" }, run.model || runConfig.model || "—"),
                                      run.status === "completed"
                                        ? createElement(
                                            "span",
                                            { className: "run-configs-list-run-action run-configs-list-run-actions" },
                                            createElement("a", {
                                              href: `/runs/${run.id}/llms_txt`,
                                              target: "_blank",
                                              rel: "noopener noreferrer",
                                              className: "run-configs-list-run-view-btn",
                                            }, "View"),
                                            createElement("a", {
                                              href: `/runs/${run.id}/debug`,
                                              target: "_blank",
                                              rel: "noopener noreferrer",
                                              className: "run-configs-list-run-view-btn run-configs-list-run-debug-btn",
                                            }, "Debug")
                                          )
                                        : run.status === "running"
                                          ? createElement("span", { className: "run-configs-list-run-action", "aria-label": "Running" },
                                              createElement("span", { className: "run-configs-list-run-spinner" }))
                                          : createElement("span", { className: "run-configs-list-run-action" })
                                    )
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
