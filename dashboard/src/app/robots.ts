import type { MetadataRoute } from "next";

// Dashboard privé : ne jamais indexer.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", disallow: "/" },
  };
}
