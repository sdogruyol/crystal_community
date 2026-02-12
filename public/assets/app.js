// Filter and Sort Functionality
document.addEventListener('DOMContentLoaded', function() {
  const developerCards = document.querySelectorAll('.developer-card');
  const filterButtons = document.querySelectorAll('.filter-button');
  
  // Filter functionality
  filterButtons.forEach(button => {
    button.addEventListener('click', function() {
      const filter = this.dataset.filter;
      
      // Update active state
      filterButtons.forEach(btn => btn.classList.remove('active'));
      this.classList.add('active');
      
      // Filter cards
      developerCards.forEach(card => {
        if (filter === 'all') {
          card.style.display = '';
        } else if (filter === 'open-to-work') {
          const hasBadge = card.querySelector('.badge-open-to-work');
          card.style.display = hasBadge ? '' : 'none';
        } else {
          card.style.display = '';
        }
        
        // Animate appearance
        if (card.style.display !== 'none') {
          card.style.animation = 'fadeIn 0.3s ease-out';
        }
      });
    });
  });
  
  // Sort functionality
  const sortSelect = document.getElementById('sort-select');
  if (sortSelect) {
    sortSelect.addEventListener('change', function() {
      const sortBy = this.value;
      const container = document.querySelector('.developer-list');
      const cards = Array.from(developerCards);
      
      cards.sort((a, b) => {
        let aValue, bValue;
        
        switch(sortBy) {
          case 'score':
            aValue = parseInt(a.dataset.score || '0');
            bValue = parseInt(b.dataset.score || '0');
            return bValue - aValue;
          case 'projects':
            aValue = parseInt(a.dataset.projects || '0');
            bValue = parseInt(b.dataset.projects || '0');
            return bValue - aValue;
          case 'name':
            aValue = a.querySelector('.developer-name')?.textContent || '';
            bValue = b.querySelector('.developer-name')?.textContent || '';
            return aValue.localeCompare(bValue);
          default:
            return 0;
        }
      });
      
      // Re-append sorted cards
      cards.forEach(card => container.appendChild(card));
    });
  }

  // Make developer cards clickable - navigate to GitHub profile
  developerCards.forEach(card => {
    card.addEventListener('click', function(e) {
      // Don't navigate if clicking on a link or button inside the card
      if (e.target.tagName === 'A' || e.target.closest('a')) {
        return;
      }
      
      const username = this.dataset.username;
      if (username) {
        window.open(`https://github.com/${username}`, '_blank', 'noopener,noreferrer');
      }
    });
  });
  
  // Smooth scroll for anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      e.preventDefault();
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        target.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
      }
    });
  });
  
  // Lazy load images
  if ('IntersectionObserver' in window) {
    const imageObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const img = entry.target;
          if (img.dataset.src) {
            img.src = img.dataset.src;
            img.removeAttribute('data-src');
            observer.unobserve(img);
          }
        }
      });
    });
    
    document.querySelectorAll('img[data-src]').forEach(img => {
      imageObserver.observe(img);
    });
  }

  // Community map with Leaflet
  const mapElement = document.getElementById('community-map');
  if (mapElement && window.L) {
    const map = L.map('community-map', {
      scrollWheelZoom: false,
      worldCopyJump: true,
    }).setView([20, 0], 2);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(map);

    const cardsWithLocation = Array.from(
      document.querySelectorAll('.developer-card[data-location]')
    ).filter(card => (card.dataset.location || '').trim() !== '');

    const geoCache = {};
    const markers = [];

    // Create custom icon with avatar
    function createAvatarIcon(avatarUrl, username, name) {
      const size = 40;
      const iconSize = [size, size];
      const iconAnchor = [size / 2, size];
      const popupAnchor = [0, -size];

      // Create a fallback avatar URL if none provided
      const avatarName = (name || username || 'User').replace(/\s+/g, '+');
      const fallbackUrl = `https://ui-avatars.com/api/?name=${encodeURIComponent(avatarName)}&size=64&background=000000&color=fff`;
      const finalAvatarUrl = avatarUrl || fallbackUrl;

      // Create HTML string for the icon
      const iconHtml = `
        <div style="
          width: ${size}px;
          height: ${size}px;
          border-radius: 50%;
          border: 3px solid #ffffff;
          box-shadow: 0 2px 8px rgba(0,0,0,0.3);
          overflow: hidden;
          background-color: #000000;
          background-image: url('${finalAvatarUrl}');
          background-size: cover;
          background-position: center;
          cursor: pointer;
          transition: transform 0.2s ease;
        "></div>
      `;

      return L.divIcon({
        html: iconHtml,
        className: 'custom-avatar-marker',
        iconSize: iconSize,
        iconAnchor: iconAnchor,
        popupAnchor: popupAnchor,
      });
    }

    function addMarkerFromCard(card, lat, lon) {
      const name = card.dataset.name || card.querySelector('.developer-name')?.textContent?.trim() || 'Developer';
      const username = card.dataset.username || '';
      const location = card.dataset.location;
      const avatarUrl = card.dataset.avatar || '';
      const openToWork = card.dataset.openToWork === 'true';

      // Create popup HTML with avatar
      const avatarName = (name || username || 'User').replace(/\s+/g, '+');
      const fallbackAvatar = `https://ui-avatars.com/api/?name=${encodeURIComponent(avatarName)}&size=64&background=000000&color=fff`;
      const finalAvatarUrl = avatarUrl || fallbackAvatar;

      const githubUrl = username ? `https://github.com/${username}` : null;

      const popupHtml = `
        <div style="text-align: center; min-width: 180px;">
          <img src="${finalAvatarUrl}" 
               alt="${name}" 
               style="width: 48px; height: 48px; border-radius: 50%; border: 2px solid #000000; margin-bottom: 8px; object-fit: cover;">
          <div>
            <strong style="display: block; margin-bottom: 4px;">${name}</strong>
            ${username ? `<span style="color: #777777; font-size: 0.875rem;">@${username}</span><br/>` : ''}
            ${location ? `<span style="color: #777777; font-size: 0.875rem;">${location}</span><br/>` : ''}
            ${openToWork ? '<span style="color:#10b981;font-weight:600;font-size:0.75rem;margin-top:4px;display:inline-block;">Open to work</span><br/>' : ''}
            ${
              githubUrl
                ? `<a href="${githubUrl}" target="_blank" rel="noopener"
                      style="
                        display:inline-flex;
                        align-items:center;
                        gap:6px;
                        margin-top:6px;
                        padding:4px 8px;
                        border-radius:999px;
                        background:#111827;
                        color:#f9fafb;
                        font-size:0.75rem;
                        text-decoration:none;
                      ">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"
                           width="14" height="14" aria-hidden="true" focusable="false"
                           fill="currentColor">
                        <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38
                          0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52
                          -.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95
                          0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09
                          2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65
                          3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/>
                      </svg>
                      <span>View on GitHub</span>
                    </a>`
                : ''
            }
          </div>
        </div>
      `;

      // Create custom icon with avatar
      const customIcon = createAvatarIcon(avatarUrl, username, name);
      
      const marker = L.marker([lat, lon], { icon: customIcon })
        .addTo(map)
        .bindPopup(popupHtml, {
          maxWidth: 200,
          className: 'custom-popup'
        });
      
      markers.push(marker);
    }

    function fitMapToMarkers() {
      if (!markers.length) return;
      
      // If only one marker, don't zoom in too much - keep default world view
      if (markers.length === 1) {
        // Just center on the marker but keep default zoom level
        map.setView(markers[0].getLatLng(), 2);
        return;
      }
      
      // For multiple markers, fit bounds but set max zoom to prevent over-zooming
      const group = L.featureGroup(markers);
      map.fitBounds(group.getBounds().pad(0.2), {
        maxZoom: 10  // Prevent zooming in too much even with multiple markers
      });
    }

    function geocodeLocation(location) {
      const cached = geoCache[location];
      if (cached) {
        return Promise.resolve(cached);
      }

      const url = `/api/geocode?q=${encodeURIComponent(location)}`;

      return fetch(url)
        .then(response => {
          if (!response.ok) return null;
          return response.json();
        })
        .then(data => {
          if (!data || data.lat == null || data.lon == null) return null;
          const point = [Number(data.lat), Number(data.lon)];
          geoCache[location] = point;
          return point;
        })
        .catch(() => null);
    }

    // Geocode and add markers (simple sequential approach to avoid hammering API)
    (async () => {
      for (const card of cardsWithLocation) {
        const location = (card.dataset.location || '').trim();
        if (!location) continue;

        const coords = await geocodeLocation(location);
        if (coords) {
          addMarkerFromCard(card, coords[0], coords[1]);
        }
      }

      fitMapToMarkers();
    })();
  }
});
