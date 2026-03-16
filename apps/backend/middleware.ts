import { NextRequest, NextResponse } from "next/server";

export function middleware(req: NextRequest) {
  const password = process.env.SITE_PASSWORD;
  if (!password) return NextResponse.next(); // no password set = open access

  // Skip auth for login page, login API, and health check
  if (req.nextUrl.pathname === "/login" || req.nextUrl.pathname === "/api/auth" || req.nextUrl.pathname === "/api/health") {
    return NextResponse.next();
  }

  // API routes: accept Bearer token OR cookie
  if (req.nextUrl.pathname.startsWith("/api/")) {
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (token === password) {
      return NextResponse.next();
    }
  }

  // Web: accept cookie
  const cookie = req.cookies.get("auth")?.value;
  if (cookie === password) {
    return NextResponse.next();
  }

  // API routes return 401, web redirects to login
  if (req.nextUrl.pathname.startsWith("/api/")) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  return NextResponse.redirect(new URL("/login", req.url));
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
