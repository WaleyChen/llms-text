import { createElement } from "react"
import { createRoot } from "react-dom/client"

function HelloReact() {
  return createElement(
    "div",
    { className: "hello-react" },
    createElement("h1", null, "Hello from React"),
    createElement("p", null, "This is the Llms Text app homepage.")
  )
}

function mount() {
  const el = document.getElementById("root")
  if (el) {
    const root = createRoot(el)
    root.render(createElement(HelloReact))
  }
}

// Turbo fires turbo:load on initial load and when navigating (e.g. back to homepage)
document.addEventListener("turbo:load", mount)
