// 안내문 슬라이드 넘기기 (test_signs/*/index.html이 함께 쓴다).
//
// - ← → 키나 클릭으로 넘기고, 마지막으로 본 장을 파일마다 기억한다.
// - `?slide=N`으로 열면 N번째 장(1부터)만 보이고 번호·안내 글자를 지운다. 넘기기도 막는다.
//   tool/render_signs.sh가 장별 PNG를 찍을 때 이 방식으로 연다.
(() => {
  const slides = [...document.querySelectorAll('.slide')];
  if (slides.length === 0) return;
  const key = 'sign:' + location.pathname;
  const fixed = Math.max(0, Math.floor(+new URLSearchParams(location.search).get('slide') || 0));
  let i = 0;
  if (fixed) {
    document.querySelectorAll('.num, .nav').forEach(e => e.remove());
    i = Math.min(fixed, slides.length) - 1;
  } else {
    try { i = Math.min(+localStorage.getItem(key) || 0, slides.length - 1); } catch (e) {}
  }

  function show(n) {
    i = (n + slides.length) % slides.length;
    slides.forEach((s, k) => s.classList.toggle('on', k === i));
    const num = document.getElementById('num');
    if (num) num.textContent = `${i + 1} / ${slides.length}`;
    if (!fixed) {
      try { localStorage.setItem(key, i); } catch (e) {}
    }
  }

  if (!fixed) {
    document.addEventListener('keydown', e => {
      if (e.key === 'ArrowRight' || e.key === ' ') show(i + 1);
      if (e.key === 'ArrowLeft') show(i - 1);
    });
    document.addEventListener('click', e => show(e.clientX > innerWidth / 3 ? i + 1 : i - 1));
  }
  show(i);
})();
