(() => {
  const themeButton = document.querySelector('.theme-toggle');
  const themeLabel = () => themeButton.setAttribute('aria-label', document.documentElement.dataset.theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
  themeLabel();
  themeButton.addEventListener('click', () => {
    const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem('theme', next); } catch (_) { /* Theme still works without storage. */ }
    themeLabel();
  });
  const nav = document.querySelector('.primary-nav');
  const button = nav.querySelector('.menu-toggle');
  button.hidden = false;
  nav.classList.add('enhanced');
  button.addEventListener('click', () => button.setAttribute('aria-expanded', String(button.getAttribute('aria-expanded') !== 'true')));
  nav.addEventListener('keydown', event => {
    if (event.key === 'Escape') { button.setAttribute('aria-expanded', 'false'); button.focus(); }
  });
})();
