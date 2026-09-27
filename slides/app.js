(() => {
  const slides = [...document.querySelectorAll('.slide')];
  const panel = document.querySelector('#overviewPanel');
  const notesButton = document.querySelector('#notes');
  const readingButton = document.querySelector('#reading');
  let index = 0;
  let touchStart = null;
  const pad = n => String(n).padStart(2, '0');
  const hashIndex = () => {
    const value = Number(location.hash.slice(1));
    return Number.isInteger(value) && value > 0 ? Math.min(value - 1, slides.length - 1) : 0;
  };
  const reading = () => document.body.classList.contains('reading-mode');
  const show = next => {
    index = (next + slides.length) % slides.length;
    slides.forEach((slide, i) => {
      slide.classList.toggle('active', i === index);
      slide.setAttribute('aria-hidden', String(!reading() && i !== index));
    });
    document.querySelector('#current').textContent = pad(index + 1);
    document.querySelector('#total').textContent = pad(slides.length);
    document.querySelector('#progressBar').style.width = `${((index + 1) / slides.length) * 100}%`;
    history.replaceState(null, '', `#${index + 1}`);
    document.title = `${slides[index].dataset.title} — RV32I SoC`;
    if (reading()) slides[index].scrollIntoView();
  };
  const overview = open => {
    panel.classList.toggle('open', open);
    panel.setAttribute('aria-hidden', String(!open));
    if (open) panel.children[index].focus();
  };
  const notes = () => {
    const open = document.body.classList.toggle('notes-open');
    notesButton.setAttribute('aria-expanded', String(open));
  };
  const toggleReading = () => {
    const enabled = document.body.classList.toggle('reading-mode');
    document.documentElement.style.overflow = enabled ? 'auto' : '';
    document.documentElement.style.height = enabled ? 'auto' : '';
    readingButton.setAttribute('aria-pressed', String(enabled));
    if (!enabled) window.scrollTo(0, 0);
    show(index);
  };
  slides.forEach((slide, i) => {
    const button = document.createElement('button');
    button.className = 'thumb';
    const number = document.createElement('span');
    number.textContent = pad(i + 1);
    const label = document.createElement('b');
    label.textContent = slide.dataset.title;
    button.append(number, label);
    button.addEventListener('click', () => {
      overview(false); show(i); document.querySelector('#overview').focus();
    });
    panel.append(button);
  });
  document.querySelector('#prev').addEventListener('click', () => show(index - 1));
  document.querySelector('#next').addEventListener('click', () => show(index + 1));
  document.querySelector('#overview').addEventListener('click', () => overview(!panel.classList.contains('open')));
  notesButton.addEventListener('click', notes);
  readingButton.addEventListener('click', toggleReading);
  document.addEventListener('keydown', event => {
    if (event.ctrlKey || event.metaKey || event.altKey || /INPUT|TEXTAREA|SELECT/.test(event.target.tagName)) return;
    if (event.key === 'Escape') {
      overview(false); document.body.classList.remove('notes-open'); notesButton.setAttribute('aria-expanded', 'false');
      return;
    }
    if (panel.classList.contains('open')) return;
    if (event.target.closest('button') && [' ', 'Enter'].includes(event.key)) return;
    if (!reading()) {
      if (['ArrowRight', 'PageDown', ' '].includes(event.key)) { event.preventDefault(); show(index + 1); }
      if (['ArrowLeft', 'PageUp'].includes(event.key)) { event.preventDefault(); show(index - 1); }
      if (event.key === 'Home') show(0);
      if (event.key === 'End') show(slides.length - 1);
    }
    if (event.key.toLowerCase() === 'o') overview(true);
    if (event.key.toLowerCase() === 'n') notes();
    if (event.key.toLowerCase() === 'r') toggleReading();
    if (event.key.toLowerCase() === 'p') window.print();
  });
  document.addEventListener('touchstart', event => { touchStart = event.changedTouches[0]; }, {passive:true});
  document.addEventListener('touchend', event => {
    if (!touchStart || reading() || document.body.classList.contains('notes-open') || panel.classList.contains('open')) return;
    const end = event.changedTouches[0];
    const dx = end.screenX - touchStart.screenX;
    const dy = end.screenY - touchStart.screenY;
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy)) show(index + (dx < 0 ? 1 : -1));
    touchStart = null;
  }, {passive:true});
  window.addEventListener('hashchange', () => show(hashIndex()));
  show(hashIndex());
})();
