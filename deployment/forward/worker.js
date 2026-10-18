// The site used to have a second copy at srujanenglabs.jsrujanreddy.workers.dev.
// GitHub Pages is now the only published copy, so this tiny Worker sends every
// visitor to the same page there. Old links keep working.
const SITE = 'https://srujanreddyj.github.io';

export default {
  fetch(request) {
    const { pathname, search } = new URL(request.url);
    // 301 = "moved for good": browsers and search engines update to the new address.
    return Response.redirect(SITE + pathname + search, 301);
  },
};
