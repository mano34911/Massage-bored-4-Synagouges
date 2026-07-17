function formatTime(date, options = {}) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: BOARD_CONFIG.timezone,
    hour: 'numeric', minute: '2-digit', second: options.seconds ? '2-digit' : undefined,
    hour12: true
  }).format(date);
}

function updateClock() {
  const now = new Date();
  document.getElementById('time').textContent = formatTime(now, { seconds: true });
  document.getElementById('date').textContent = new Intl.DateTimeFormat('en-US', {
    timeZone: BOARD_CONFIG.timezone,
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  }).format(now);
}

function loadConfig() {
  document.querySelector('h1').textContent = BOARD_CONFIG.title;
  document.querySelector('.dedication').innerHTML = BOARD_CONFIG.dedication.replace('זהבה חלא', '<strong>זהבה חלא</strong>');
  document.getElementById('shacharit').textContent = BOARD_CONFIG.prayerTimes.shacharit;
  document.getElementById('mincha').textContent = BOARD_CONFIG.prayerTimes.mincha;
  document.getElementById('maariv').textContent = BOARD_CONFIG.prayerTimes.maariv;
  document.getElementById('announcement').textContent = BOARD_CONFIG.announcement;
  document.getElementById('locationLabel').textContent = `Location: ${BOARD_CONFIG.locationName}`;
  const ul = document.getElementById('contributors');
  ul.innerHTML = '';
  BOARD_CONFIG.contributors.forEach(name => {
    const li = document.createElement('li');
    li.textContent = name;
    ul.appendChild(li);
  });
  const ticker = document.getElementById('contributorsTicker');
  if (ticker) ticker.textContent = BOARD_CONFIG.contributors.join('   ✦   ');
}

async function loadJewishInfo() {
  const today = new Date();
  const y = new Intl.DateTimeFormat('en-CA', { timeZone: BOARD_CONFIG.timezone, year: 'numeric' }).format(today);
  const m = new Intl.DateTimeFormat('en-CA', { timeZone: BOARD_CONFIG.timezone, month: '2-digit' }).format(today);
  const d = new Intl.DateTimeFormat('en-CA', { timeZone: BOARD_CONFIG.timezone, day: '2-digit' }).format(today);
  const url = `https://www.hebcal.com/shabbat?cfg=json&latitude=${BOARD_CONFIG.latitude}&longitude=${BOARD_CONFIG.longitude}&tzid=${BOARD_CONFIG.timezone}&m=50&b=18&gy=${y}&gm=${m}&gd=${d}`;
  try {
    const res = await fetch(url);
    const data = await res.json();
    const hebDate = data.items.find(i => i.category === 'hebdate');
    const parasha = data.items.find(i => i.category === 'parashat');
    const candle = data.items.find(i => i.category === 'candles');
    const havdalah = data.items.find(i => i.category === 'havdalah');
    if (hebDate) document.getElementById('hebrewDate').textContent = hebDate.hebrew || hebDate.title;
    if (parasha) document.getElementById('parasha').textContent = parasha.hebrew || parasha.title;
    if (candle) document.getElementById('sundown').textContent = formatTime(new Date(candle.date));
    if (havdalah) document.getElementById('sundown').textContent = formatTime(new Date(havdalah.date));
  } catch (e) {
    document.getElementById('hebrewDate').textContent = 'Check internet connection';
  }
}

async function loadSunriseSunset() {
  const url = `https://api.sunrise-sunset.org/json?lat=${BOARD_CONFIG.latitude}&lng=${BOARD_CONFIG.longitude}&formatted=0`;
  try {
    const res = await fetch(url);
    const data = await res.json();
    document.getElementById('sunrise').textContent = formatTime(new Date(data.results.sunrise));
    document.getElementById('sundown').textContent = formatTime(new Date(data.results.sunset));
  } catch (e) {
    document.getElementById('sunrise').textContent = 'Offline';
    document.getElementById('sundown').textContent = 'Offline';
  }
}

loadConfig();
updateClock();
loadSunriseSunset();
loadJewishInfo();
setInterval(updateClock, 1000);
setInterval(() => { loadSunriseSunset(); loadJewishInfo(); }, 1000 * 60 * 60);
