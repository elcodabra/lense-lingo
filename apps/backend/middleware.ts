import { NextRequest, NextResponse } from "next/server";

export function middleware(req: NextRequest) {
  const password = process.env.SITE_PASSWORD;
  if (!password) return NextResponse.next(); // no password set = open access

  // Skip auth for login page and login API
  if (req.nextUrl.pathname === "/login" || req.nextUrl.pathname === "/api/auth") {
    return NextResponse.next();
  }

  const cookie = req.cookies.get("auth")?.value;
  if (cookie === password) {
    return NextResponse.next();
  }

  return NextResponse.redirect(new URL("/login", req.url));
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
