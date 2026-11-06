document.addEventListener("submit", event => {
  const form = event.target.closest("[data-ipa-upload]")
  if (!form) return

  const status = form.querySelector("[data-ipa-upload-status]")
  const file = form.querySelector('input[type="file"]').files[0]
  if (file && file.size > 250 * 1024 * 1024) {
    event.preventDefault()
    status.textContent = "Choose an IPA of 250 MiB or less. The current download has not changed."
    return
  }

  form.setAttribute("aria-busy", "true")
  form.querySelector('button[type="submit"]').disabled = true
  status.textContent = "Uploading IPA. Keep this page open."
})

window.addEventListener("pageshow", () => {
  document.querySelectorAll("[data-ipa-upload]").forEach(form => {
    form.removeAttribute("aria-busy")
    form.querySelector('button[type="submit"]').disabled = false
    form.querySelector("[data-ipa-upload-status]").textContent = ""
  })
})
