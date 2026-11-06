const copyStates = new WeakMap()

function selectField(input) {
  input.focus({preventScroll: true})
  input.select()
  input.setSelectionRange(0, input.value.length)
}

function legacyCopy(input) {
  try {
    selectField(input)
    return document.execCommand("copy") === true
  } catch (_error) {
    return false
  }
}

async function copyField(button) {
  const field = button.closest("[data-device-copy-field]")
  const input = field?.querySelector("input[readonly]")
  const feedback = field?.querySelector("[data-device-copy-feedback]")
  const label = button.querySelector("[data-device-copy-label]")

  if (!input || !feedback || !label || button.disabled) return

  const state = copyStates.get(button) || {timer: null}
  window.clearTimeout(state.timer)
  state.timer = null
  copyStates.set(button, state)
  feedback.textContent = ""
  button.dataset.copyState = "copying"
  button.disabled = true
  button.setAttribute("aria-busy", "true")
  label.textContent = "Copying…"

  let copied = false

  if (input.value) {
    try {
      // Call writeText within the click gesture, before any other awaited work.
      if (window.isSecureContext && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(input.value)
        copied = true
      } else {
        copied = legacyCopy(input)
      }
    } catch (_error) {
      if (button.isConnected) copied = legacyCopy(input)
    }
  }

  if (!button.isConnected) return

  button.disabled = false
  button.removeAttribute("aria-busy")

  if (copied) {
    button.dataset.copyState = "copied"
    label.textContent = "Copied"
    feedback.textContent = `${button.dataset.copyName} copied.`
    if (document.activeElement === input) button.focus({preventScroll: true})

    state.timer = window.setTimeout(() => {
      if (button.isConnected) {
        delete button.dataset.copyState
        label.textContent = "Copy"
        feedback.textContent = ""
      }
      state.timer = null
    }, 4000)
  } else {
    button.dataset.copyState = "manual"
    label.textContent = "Copy"

    if (input.value) {
      try {
        selectField(input)
        feedback.textContent = "Text selected. Touch and hold to copy, or use your keyboard’s copy shortcut."
      } catch (_error) {
        feedback.textContent = "Copy was blocked. Select the text above and copy it manually."
      }
    } else {
      feedback.textContent = "Nothing to copy. Refresh this page and try again."
    }
  }
}

document.addEventListener("click", event => {
  const button = event.target instanceof Element
    ? event.target.closest("button[data-device-copy]")
    : null

  if (!button) return
  event.preventDefault()
  void copyField(button)
})
