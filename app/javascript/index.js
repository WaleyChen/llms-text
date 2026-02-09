import { createElement, useState, useEffect } from "react"
import { createRoot } from "react-dom/client"

function HomePage() {
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  const [sites, setSites] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch("/sites.json", {
      headers: { Accept: "application/json" },
    })
      .then((res) => res.ok ? res.json() : [])
      .then((data) => {
        setSites(Array.isArray(data) ? data : [])
      })
      .catch(() => setSites([]))
      .finally(() => setLoading(false))
  }, [])

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
                ...sites.map((site) =>
                  createElement(
                    "li",
                    { key: site.id, className: "sites-list-item" },
                    createElement("a", { href: site.url, target: "_blank", rel: "noopener noreferrer" }, site.url)
                  )
                )
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
