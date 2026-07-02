import type { NextConfig } from "next";
import path from "node:path";

const LIB_DIR = path.resolve(__dirname, "../lib");

const nextConfig: NextConfig = {
  allowedDevOrigins: ["localhost", "127.0.0.1", "100.97.9.56"],
  typescript: {
    ignoreBuildErrors: true,
  },
  serverExternalPackages: ["@erp-lib/native/vision-ocr"],
  webpack: (config) => {
    config.resolve = config.resolve ?? {};
    config.resolve.alias = {
      ...(config.resolve.alias as Record<string, string> | undefined),
      '@erp-lib': LIB_DIR,
      '@erp-lib/native/vision-ocr': path.resolve(LIB_DIR, 'native/vision-ocr'),
    };
    return config;
  },
  turbopack: {
    resolveAlias: {
      '@erp-lib': LIB_DIR,
      '@erp-lib/native/vision-ocr': path.resolve(LIB_DIR, 'native/vision-ocr'),
    },
  },
};

export default nextConfig;