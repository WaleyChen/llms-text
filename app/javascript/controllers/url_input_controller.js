import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="url-input"
export default class extends Controller {
  static targets = ["input"]

  static values = {
    placeholder: { type: String, default: "https://example.com" },
  }

  clear() {
    if (this.hasInputTarget) this.inputTarget.value = ""
  }
}
