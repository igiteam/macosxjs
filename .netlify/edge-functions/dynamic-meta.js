import { HTMLRewriter } from "https://raw.githubusercontent.com/worker-tools/html-rewriter/master/index.ts";

const fallbackImageUrl = "https://cdn.sdappnet.cloud/rtx/images/ytembed.png";
const defaultTitle = "YouTube Full-Screen";
const WESERV_BASE_URL = "https://img.sdappnet.cloud";

class MetaRewriter {
  constructor(imageUrl, videoTitle) {
    this.imageUrl = imageUrl;
    this.videoTitle = videoTitle;
  }

  element(element) {
    const property = element.getAttribute("property");
    const name = element.getAttribute("name");

    if (property === "og:image" || name === "twitter:image") {
      element.setAttribute("content", this.imageUrl);
    }
    if (property === "og:title" || name === "twitter:title") {
      element.setAttribute("content", this.videoTitle);
    }
  }
}

class TitleRewriter {
  constructor(videoTitle) {
    this.videoTitle = videoTitle;
  }

  element(element) {
    element.setInnerContent(this.videoTitle);
  }
}

class HeadRewriter {
  constructor(videoId) {
    this.videoId = videoId;
    if (videoId) {
      // Use weserv for cropped favicons, direct YouTube for main thumbnails
      this.faviconUrl = getCroppedFaviconUrl(videoId, 512);
      this.iconUrl = getCroppedFaviconUrl(videoId, 512);
      this.thumbnailUrl = `https://i.ytimg.com/vi/${videoId}/maxresdefault.jpg`;
    }
    this.hasFavicon = false;
    this.hasAppleTouchIcon = false;
    this.hasIcon192 = false;
    this.hasIcon512 = false;
  }

  element(element) {
    element.onEndTag((endTag) => {
      if (!this.videoId) return;

      let additionalHtml = "";

      if (!this.hasFavicon) {
        additionalHtml += `<link rel="icon" href="${this.iconUrl}" type="image/png">`;
      }
      if (!this.hasAppleTouchIcon) {
        additionalHtml += `<link rel="apple-touch-icon" sizes="180x180" href="${this.faviconUrl}">`;
      }
      if (!this.hasIcon192) {
        additionalHtml += `<link rel="icon" type="image/png" sizes="192x192" href="${this.faviconUrl}">`;
      }
      if (!this.hasIcon512) {
        additionalHtml += `<link rel="icon" type="image/png" sizes="512x512" href="${this.faviconUrl}">`;
      }

      if (additionalHtml) {
        endTag.before(additionalHtml, { html: true });
      }
    });
  }
}

class LinkRewriter {
  constructor(videoId, headRewriter) {
    this.videoId = videoId;
    this.headRewriter = headRewriter;
    if (videoId) {
      this.faviconUrl = getCroppedFaviconUrl(videoId, 512);
      this.iconUrl = getCroppedFaviconUrl(videoId, 512);
    }
  }

  element(element) {
    const rel = element.getAttribute("rel");
    const sizes = element.getAttribute("sizes");

    if (!rel || !this.videoId) return;

    if (rel === "icon") {
      if (sizes === "192x192" || sizes === "512x512") {
        // Use cropped favicon for larger sizes
        element.setAttribute("href", this.faviconUrl);
        element.setAttribute("type", "image/png");
        if (sizes === "192x192") this.headRewriter.hasIcon192 = true;
        if (sizes === "512x512") this.headRewriter.hasIcon512 = true;
      } else if (!sizes || sizes === "") {
        // Regular favicon
        element.setAttribute("href", this.iconUrl);
        element.setAttribute("type", "image/png");
        this.headRewriter.hasFavicon = true;
      }
    } else if (rel === "apple-touch-icon") {
      element.setAttribute("href", this.faviconUrl);
      this.headRewriter.hasAppleTouchIcon = true;
    }
  }
}

// Helper function to get cropped favicon from weserv
function getCroppedFaviconUrl(videoId, size = 512) {
  const youtubeUrl = `https://i.ytimg.com/vi/${videoId}/maxresdefault.jpg`;
  const encodedUrl = encodeURIComponent(youtubeUrl);
  return `${WESERV_BASE_URL}/?url=${encodedUrl}&w=${size}&h=${size}&fit=cover&output=png`;
}

function extractYouTubeId(url) {
  if (!url) return null;
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\?\/\s]{11})/,
    /^([^&\?\/\s]{11})$/,
  ];

  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }
  return null;
}

function decodeYouTubeCode(shortCode) {
  if (!shortCode) return null;
  try {
    let base64 = shortCode.replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4) {
      base64 += "=";
    }
    return atob(base64);
  } catch (e) {
    console.error("Failed to decode YouTube code:", e);
    return null;
  }
}

async function fetchYouTubeTitle(videoId) {
  if (!videoId) return `YouTube Video`;

  try {
    const response = await fetch(
      `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`
    );

    if (response.ok) {
      const data = await response.json();
      return data.title || `YouTube Video: ${videoId}`;
    }

    return `YouTube Video: ${videoId}`;
  } catch (error) {
    console.error("Failed to fetch YouTube title:", error);
    return `YouTube Video: ${videoId}`;
  }
}

export default async (request, context) => {
  try {
    const url = new URL(request.url);

    // Get the first query parameter key
    const params = url.searchParams;
    let code = null;
    for (const key of params.keys()) {
      code = key;
      break;
    }

    let imageUrl = fallbackImageUrl;
    let videoTitle = defaultTitle;
    let videoId = null;

    // Try to extract YouTube video ID from URL parameter
    if (code) {
      try {
        const decoded = decodeYouTubeCode(code);
        videoId = extractYouTubeId(decoded) || decoded;

        if (videoId && videoId.length === 11) {
          imageUrl = `https://i.ytimg.com/vi/${videoId}/maxresdefault.jpg`;
          videoTitle = await fetchYouTubeTitle(videoId);
        }
      } catch (e) {
        console.error("Failed to process URL parameter:", e);
      }
    }

    const response = await context.next();
    const contentType = response.headers.get("content-type") || "";

    if (!contentType.includes("text/html")) {
      return response;
    }

    // Create HeadRewriter instance
    const headRewriter = new HeadRewriter(videoId);

    // Start with basic rewriters
    let rewriter = new HTMLRewriter()
      .on("meta", new MetaRewriter(imageUrl, videoTitle))
      .on("title", new TitleRewriter(videoTitle))
      .on("head", headRewriter);

    // Add link rewriter only if we have a videoId
    if (videoId) {
      const linkRewriter = new LinkRewriter(videoId, headRewriter);
      rewriter = rewriter.on("link", linkRewriter);
    }

    return rewriter.transform(response);
  } catch (error) {
    console.error("Edge function error:", error);

    // Return a fallback response if everything fails
    return new Response(
      `<html><body><h1>YouTube Embed</h1><p>Loading content...</p></body></html>`,
      {
        status: 200,
        headers: { "content-type": "text/html" },
      }
    );
  }
};

export const config = {
  path: "/*",
};
