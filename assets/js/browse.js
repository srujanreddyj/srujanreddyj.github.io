(() => {
  const library = document.querySelector('[data-browser]');
  if (!library) return;
  const form = library.querySelector('form');
  const rows = Array.from(library.querySelectorAll('[data-entry]'));
  const results = library.querySelector('[data-results]');
  const empty = library.querySelector('[data-empty]');
  const search = form.elements.namedItem('q');
  const topic = form.elements.namedItem('topic');
  const type = form.elements.namedItem('type');
  const known = (select, value) => select && Array.from(select.options).some(option => option.value === value) ? value : '';
  const restore = () => {
    const params = new URLSearchParams(location.search);
    search.value = params.get('q') || '';
    if (topic) topic.value = known(topic, params.get('topic') || '');
    if (type) type.value = known(type, params.get('type') || '');
  };
  const filter = (updateUrl) => {
    const query = search.value.trim().toLocaleLowerCase();
    const terms = query.split(/\s+/).filter(Boolean);
    const selectedTopic = topic ? topic.value : library.dataset.fixedTopic;
    const selectedType = type ? type.value : library.dataset.fixedKind;
    let count = 0;
    rows.forEach(row => {
      const text = `${row.dataset.title} ${row.dataset.summary}`.toLocaleLowerCase();
      const matches = terms.every(term => text.includes(term)) &&
        (!selectedTopic || row.dataset.topics.split(' ').includes(selectedTopic)) &&
        (!selectedType || row.dataset.kind === selectedType);
      row.hidden = !matches;
      if (matches) count += 1;
    });
    results.textContent = `${count} ${count === 1 ? 'item' : 'items'} · newest first`;
    empty.hidden = count > 0;
    if (updateUrl) {
      const url = new URL(location.href);
      ['q', 'topic', 'type'].forEach(key => url.searchParams.delete(key));
      if (search.value.trim()) url.searchParams.set('q', search.value.trim());
      if (topic && topic.value) url.searchParams.set('topic', topic.value);
      if (type && type.value) url.searchParams.set('type', type.value);
      history.replaceState(null, '', url);
    }
  };
  form.hidden = false;
  restore();
  filter(false);
  form.addEventListener('submit', event => { event.preventDefault(); filter(true); });
  form.addEventListener('input', () => filter(true));
  form.addEventListener('change', () => filter(true));
  form.addEventListener('reset', () => { requestAnimationFrame(() => { filter(true); search.focus(); }); });
  window.addEventListener('popstate', () => { restore(); filter(false); });
  window.addEventListener('pageshow', () => { restore(); filter(false); });
})();
