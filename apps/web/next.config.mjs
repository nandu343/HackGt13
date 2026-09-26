/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    typedRoutes: false
  },
  // Optional same-origin proxy if a client points at /backend/* (direct 127.0.0.1:8000 remains default).
  async rewrites() {
    return [
      {
        source: '/backend/:path*',
        destination: 'http://127.0.0.1:8000/:path*'
      }
    ];
  }
};

export default nextConfig;
