import { createElement, useState, useEffect } from "react"
import { createRoot } from "react-dom/client"

function HomePage() {
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  const [sites, setSites] = useState([])
  const [loading, setLoading] = useState(true)
  const [expandedSiteId, setExpandedSiteId] = useState(null)
  const [runsBySiteId, setRunsBySiteId] = useState({})
  const [loadingRunsForId, setLoadingRunsForId] = useState(null)

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
                      }, site.url)
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
