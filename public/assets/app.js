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
});
