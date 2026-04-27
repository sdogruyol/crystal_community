(function () {
  const dataScript = document.getElementById('stats-timeseries-data');
  const canvasRepos = document.getElementById('stats-chart-repos');
  const canvasStars = document.getElementById('stats-chart-stars');
  if (!dataScript || !canvasRepos || !canvasStars || typeof Chart === 'undefined') {
    return;
  }

  var payload;
  try {
    payload = JSON.parse(dataScript.textContent || '{}');
  } catch (e) {
    return;
  }

  if (!payload.labels || !payload.repos || !payload.stars) {
    return;
  }
  if (payload.labels.length < 2) {
    return;
  }

  const style = getComputedStyle(document.documentElement);
  const textMuted = (style.getPropertyValue('--text-secondary') || '#6b7280').trim() || '#6b7280';
  const border = (style.getPropertyValue('--border-color') || '#e5e7eb').trim() || '#e5e7eb';

  const baseOptions = {
    responsive: true,
    maintainAspectRatio: true,
    aspectRatio: 1.75,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: { display: false },
      tooltip: {
        callbacks: {
          label: function (ctx) {
            var v = ctx.parsed.y;
            if (v == null) {
              return '';
            }
            return Number(v).toLocaleString();
          },
        },
      },
    },
    scales: {
      x: {
        ticks: { color: textMuted, maxRotation: 45, minRotation: 0, autoSkip: true },
        grid: { color: border },
      },
    },
  };

  new Chart(canvasRepos.getContext('2d'), {
    type: 'line',
    data: {
      labels: payload.labels,
      datasets: [
        {
          label: 'Repos',
          data: payload.repos,
          borderColor: '#111827',
          backgroundColor: 'rgba(17, 24, 39, 0.08)',
          fill: false,
          tension: 0.2,
          pointRadius: 2,
        },
      ],
    },
    options: {
      ...baseOptions,
      scales: {
        ...baseOptions.scales,
        y: {
          type: 'linear',
          position: 'left',
          ticks: { color: textMuted, callback: function (v) { return Number(v).toLocaleString(); } },
          grid: { color: border },
        },
      },
    },
  });

  new Chart(canvasStars.getContext('2d'), {
    type: 'line',
    data: {
      labels: payload.labels,
      datasets: [
        {
          label: 'Total stars',
          data: payload.stars,
          borderColor: '#ea580c',
          backgroundColor: 'rgba(234, 88, 12, 0.1)',
          fill: false,
          tension: 0.2,
          pointRadius: 2,
        },
      ],
    },
    options: {
      ...baseOptions,
      scales: {
        ...baseOptions.scales,
        y: {
          type: 'linear',
          position: 'left',
          ticks: { color: textMuted, callback: function (v) { return Number(v).toLocaleString(); } },
          grid: { color: border },
        },
      },
    },
  });
})();
