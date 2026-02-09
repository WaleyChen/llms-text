/**
 * Minimal Action Cable client (no gem asset). Compatible with Rails Action Cable server.
 * Usage: ActionCable.createConsumer(url).subscriptions.create({ channel, site_id }, { received })
 */
function createConsumer(url) {
  let ws = null
  const subscriptions = new Map()
  const protocols = ["actioncable-v1-json", "actioncable-unsupported"]

  function connect() {
    ws = new WebSocket(url, protocols)
    ws.onopen = () => {
      subscriptions.forEach((sub) => {
        if (sub.identifier) send({ command: "subscribe", identifier: sub.identifier })
      })
    }
    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data)
        if (msg.identifier && msg.message !== undefined) {
          const sub = subscriptions.get(msg.identifier)
          if (sub && sub.received) sub.received(msg.message)
        }
      } catch (_) {}
    }
    ws.onerror = () => { console.warn("[Cable] WebSocket error for", url) }
    ws.onclose = (event) => {
      if (event.code !== 1000) console.warn("[Cable] WebSocket closed", event.code, event.reason || "(no reason)")
      setTimeout(connect, 1000)
    }
  }

  function send(obj) {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj))
  }

  connect()

  return {
    subscriptions: {
      create(identifier, callbacks = {}) {
        const idStr = typeof identifier === "string" ? identifier : JSON.stringify(identifier)
        subscriptions.set(idStr, { identifier: idStr, received: callbacks.received })
        if (ws && ws.readyState === WebSocket.OPEN) send({ command: "subscribe", identifier: idStr })
        return {
          unsubscribe() {
            send({ command: "unsubscribe", identifier: idStr })
            subscriptions.delete(idStr)
          },
        }
      },
    },
  }
}

const ActionCable = { createConsumer }
export default ActionCable
