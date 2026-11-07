import { Controller } from "@hotwired/stimulus"

// The only TypeScript in the app: feedback while the export form is submitted.
// The server redirects straight to the history page, so there is no polling.
export default class extends Controller<HTMLFormElement> {
  static targets = ["button", "message"]

  declare readonly buttonTarget: HTMLInputElement
  declare readonly messageTarget: HTMLElement

  started(): void {
    this.buttonTarget.disabled = true
    this.messageTarget.textContent = "Starting export…"
    this.messageTarget.hidden = false
  }

  finished(event: CustomEvent<{ success: boolean }>): void {
    if (event.detail.success) return

    this.buttonTarget.disabled = false
    this.messageTarget.hidden = true
  }
}
