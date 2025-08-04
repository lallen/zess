function initRuntime() {
  document.querySelectorAll("a").forEach((a) => {
    a.onclick = (e) => {
      if (a.href.startsWith(window.location.origin)) {
        e.preventDefault();
        fetch(a.href)
          .then((r) => r.text())
          .then((html) => {
            document.open();
            document.write(html);
            document.close();
          });
      }
    };
  });
}
initRuntime();
