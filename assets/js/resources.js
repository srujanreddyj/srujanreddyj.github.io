(() => {
  const library = document.querySelector('[data-resources]');
  if (!library) return;
  const form = library.querySelector('form');
  const fields = ['q', 'topic', 'purpose', 'type', 'status'];
  const rows = Array.from(library.querySelectorAll('[data-resource]')).map(element => ({
    element, topics: JSON.parse(element.dataset.topics), text: element.textContent.toLocaleLowerCase()
  }));
  const restore = () => {
    const params = new URLSearchParams(location.search);
    fields.forEach(key => {
      const input = form.elements.namedItem(key);
      const value = params.get(key) || '';
      input.value = key === 'q' || Array.from(input.options).some(option => option.value === value) ? value : '';
    });
  };
  const filter = (updateUrl = true) => {
    const selected = Object.fromEntries(fields.map(key => [key, form.elements.namedItem(key).value.trim()]));
    const terms = selected.q.toLocaleLowerCase().split(/\s+/).filter(Boolean);
    let count = 0;
    rows.forEach(({element, topics, text}) => {
      const visible = terms.every(term => text.includes(term)) && (!selected.topic || topics.includes(selected.topic)) &&
        ['purpose', 'type', 'status'].every(key => !selected[key] || element.dataset[key] === selected[key]);
      element.hidden = !visible;
      if (visible) count++;
    });
    library.querySelectorAll('[data-resource-group]').forEach(group => {
      group.hidden = !group.querySelector('[data-resource]:not([hidden])');
    });
    library.querySelector('[data-results]').textContent = `${count} ${count === 1 ? 'resource' : 'resources'} · grouped by purpose`;
    library.querySelector('[data-empty]').hidden = count > 0;
    if (updateUrl) {
      const url = new URL(location.href);
      fields.forEach(key => { url.searchParams.delete(key); if (selected[key]) url.searchParams.set(key, selected[key]); });
      history.replaceState(null, '', url);
    }
  };
  form.hidden = false;
  restore(); filter(false);
  form.addEventListener('input', () => filter());
  form.addEventListener('change', () => filter());
  form.addEventListener('submit', event => { event.preventDefault(); filter(); });
  form.addEventListener('reset', () => requestAnimationFrame(() => { filter(); form.elements.namedItem('q').focus(); }));
  window.addEventListener('popstate', () => { restore(); filter(false); });
  window.addEventListener('pageshow', () => { restore(); filter(false); });
})();
