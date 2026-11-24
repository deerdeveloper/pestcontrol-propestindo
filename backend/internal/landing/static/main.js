// Interaksi kecil landing page Propestindo (tanpa library).
(function () {
  var WA = '6282115208851' // nomor WhatsApp tujuan formulir (format internasional, tanpa +)
  document.documentElement.classList.add('js')

  // Header berubah saat di-scroll
  var nav = document.querySelector('.nav')
  function onScroll() { nav.classList.toggle('scrolled', window.scrollY > 8) }
  window.addEventListener('scroll', onScroll, { passive: true })
  onScroll()

  // Menu HP
  var btn = document.querySelector('.menu-btn')
  var menu = document.getElementById('menu')
  btn.addEventListener('click', function () {
    var open = menu.classList.toggle('open')
    btn.setAttribute('aria-expanded', open ? 'true' : 'false')
  })
  menu.addEventListener('click', function (e) {
    if (e.target.closest('a')) { menu.classList.remove('open'); btn.setAttribute('aria-expanded', 'false') }
  })

  // Animasi muncul
  var items = document.querySelectorAll('.reveal')
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target) }
      })
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 })
    items.forEach(function (el) { io.observe(el) })
  } else {
    items.forEach(function (el) { el.classList.add('in') })
  }

  // Satu FAQ terbuka dalam satu waktu
  var faqs = document.querySelectorAll('.faq details')
  faqs.forEach(function (d) {
    d.addEventListener('toggle', function () {
      if (d.open) faqs.forEach(function (o) { if (o !== d) o.open = false })
    })
  })

  // Formulir -> WhatsApp
  var form = document.getElementById('cform')
  var err = document.getElementById('ferr')
  form.addEventListener('submit', function (e) {
    e.preventDefault()
    var f = form.elements
    var nama = f.nama.value.trim()
    var hp = f.hp.value.trim()
    f.nama.classList.toggle('bad', !nama)
    f.hp.classList.toggle('bad', !/^[+0-9][0-9\s-]{7,}$/.test(hp))
    if (!nama || !/^[+0-9][0-9\s-]{7,}$/.test(hp)) {
      err.textContent = 'Mohon isi nama dan nomor WhatsApp yang valid.'
      return
    }
    err.textContent = ''
    var lines = [
      'Halo Propestindo, saya ingin minta survei gratis.',
      '',
      'Nama: ' + nama,
      'No. WhatsApp: ' + hp,
      'Area: ' + (f.area.value.trim() || '-'),
      'Jenis properti: ' + f.properti.value,
      'Jenis hama: ' + f.hama.value,
    ]
    if (f.catatan.value.trim()) lines.push('Catatan: ' + f.catatan.value.trim())
    window.open('https://wa.me/' + WA + '?text=' + encodeURIComponent(lines.join('\n')), '_blank', 'noopener')
  })

  var yr = document.getElementById('yr')
  if (yr) yr.textContent = new Date().getFullYear()
})()
