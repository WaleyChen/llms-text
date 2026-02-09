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
  const cableRef = useRef(null)
  const subscriptionRef = useRef(null)

  useEffect(() => {
    fetch("/sites.json", {
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
    fetch(`/sites/${expandedSiteId}/runs.json`, { headers: { Accept: "application/json" } })
      .then((res) => (res.ok ? res.json() : []))
      .then((data) => {
        setRunsBySiteId((prev) => ({ ...prev, [expandedSiteId]: Array.isArray(data) ? data : [] }))
      })
      .catch(() => setRunsBySiteId((prev) => ({ ...prev, [expandedSiteId]: [] })))
      .finally(() => setLoadingRunsForId(null))
  }, [expandedSiteId])

  useEffect(() => {
    if (expandedSiteId == null) {
      if (subscriptionRef.current) {
        subscriptionRef.current.unsubscribe()
        subscriptionRef.current = null
      }
      return
    }
    const siteId = Number(expandedSiteId)
    if (!siteId) return
    let cancelled = false
    function connect() {
      const ActionCable = window.ActionCable
      if (cancelled || !ActionCable?.createConsumer) return
      try {
        const url = (window.location.protocol === "https:" ? "wss:" : "ws:") + "//" + window.location.host + "/cable"
        if (!cableRef.current) cableRef.current = ActionCable.createConsumer(url)
        if (!cableRef.current) return
        const sub = cableRef.current.subscriptions.create(
          { channel: "SiteChannel", site_id: siteId },
          {
            received(data) {
              const run = data.run
              if (!run || !run.id) return
              console.log("[Cable] run update", run.id, run.status)
              const runSiteId = run.site_id
              setRunsBySiteId((prev) => {
                const list = prev[runSiteId] || []
                const idx = list.findIndex((r) => r.id === run.id)
                const next = idx >= 0 ? [...list.slice(0, idx), run, ...list.slice(idx + 1)] : [run, ...list]
                return { ...prev, [runSiteId]: next }
              })
            },
          }
        )
        subscriptionRef.current = sub
      } catch (e) {
        console.warn("[Cable] subscribe failed", e)
      }
    }
    if (window.ActionCable) {
      connect()
    } else {
      document.addEventListener("actioncable:ready", connect, { once: true })
    }
    return () => {
      cancelled = true
      document.removeEventListener("actioncable:ready", connect)
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
    fetch(`/sites/${siteId}/runs`, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
      },
      body: JSON.stringify({}),
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
      fetch(`/sites/${siteId}/runs.json`, { headers: { Accept: "application/json" } })
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
            action: "/sites",
            method: "post",
            acceptCharset: "utf-8",
          },
          createElement("input", {
            type: "hidden",
            name: "authenticity_token",
            value: csrfToken,
          }),
          createElement("input", {
            id: "url",
            type: "url",
            name: "site[url]",
            placeholder: "https://example.com",
            autoComplete: "url",
            className: "prompt-input",
            "data-url-input-target": "input",
          }),
          createElement(
            "div",
            { className: "prompt-box-footer" },
            createElement("button", {
              type: "submit",
              className: "prompt-submit-btn",
            }, "Generate")
          )
        )
      ),
      createElement(
        "div",
        { className: "sites-list-wrapper" },
        loading
          ? createElement("p", { className: "sites-list-message" }, "Loading…")
          : sites.length === 0
            ? createElement("p", { className: "sites-list-message" }, "No sites yet. Add one above.")
            : createElement(
                "ul",
                { className: "sites-list" },
                ...sites.map((site) => {
                  const isExpanded = expandedSiteId === site.id
                  const runs = runsBySiteId[site.id]
                  const loadingRuns = loadingRunsForId === site.id
                  return createElement(
                    "li",
                    { key: site.id, className: "sites-list-item" },
                    createElement(
                      "button",
                      {
                        type: "button",
                        className: "sites-list-site-row",
                        onClick: () => toggleSiteRuns(site.id),
                      },
                      createElement("span", { className: "sites-list-site-expand" }, isExpanded ? "▼" : "▶"),
                      createElement("a", {
                        href: site.url,
                        target: "_blank",
                        rel: "noopener noreferrer",
                        className: "sites-list-site-url",
                        onClick: (e) => e.stopPropagation(),
                      }, site.url),
                      createElement("button", {
                        type: "button",
                        className: "sites-list-run-btn",
                        "aria-label": "Start run",
                        disabled: startingRunForId === site.id,
                        onClick: (e) => startRun(site.id, e),
                      }, startingRunForId === site.id ? "…" : "Run")
                    ),
                    isExpanded &&
                      createElement(
                        "div",
                        { className: "sites-list-runs" },
                        loadingRuns
                          ? createElement("p", { className: "sites-list-runs-loading" }, "Loading runs…")
                          : !runs || runs.length === 0
                            ? createElement("p", { className: "sites-list-runs-empty" }, "No runs yet.")
                            : createElement(
                                "ul",
                                { className: "sites-list-runs-list" },
                                ...runs.map((run) =>
                                  createElement(
                                    "li",
                                    { key: run.id, className: "sites-list-run" },
                                    createElement("span", { className: "sites-list-run-status" }, run.status),
                                    run.started_at &&
                                      createElement("span", { className: "sites-list-run-time" },
                                        new Date(run.started_at).toLocaleString())
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
