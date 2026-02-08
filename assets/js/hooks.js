let Hooks = {};

Hooks.Clipboard = {
  mounted() {
    this.handleEvent("copy-to-clipboard", ({ text: text }) => {
      navigator.clipboard.writeText(text).then(() => {
        this.pushEventTo(this.el, "copied-to-clipboard", { text: text });
        setTimeout(() => {
          this.pushEventTo(this.el, "reset-copied", {});
        }, 2000);
      });
    });
  },
};

Hooks.ChatWidgetInput = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        this.submitMessage();
      }
    });
    this.el.addEventListener("submit-chat", () => {
      this.submitMessage();
    });
  },
  submitMessage() {
    const value = this.el.value.trim();
    if (value !== "") {
      const target = this.el.dataset.target;
      this.pushEventTo(target, "send_message", { message: value });
      this.el.value = "";
    }
  },
};

Hooks.ScrollBottom = {
  mounted() {
    this.scrollToBottom();
    this.observer = new MutationObserver(() => this.scrollToBottom());
    this.observer.observe(this.el, { childList: true, subtree: true });
  },
  updated() {
    this.scrollToBottom();
  },
  destroyed() {
    if (this.observer) this.observer.disconnect();
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

export default Hooks;
