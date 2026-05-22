import Link from "next/link";

export function Nav() {
  return (
    <nav className="border-b border-border bg-surface/80 backdrop-blur supports-[backdrop-filter]:bg-surface/60">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
        <Link
          href="/"
          className="font-mono text-sm tracking-tight text-foreground"
        >
          cooked<span className="text-muted-foreground">/dashboard</span>
        </Link>
        <div className="flex items-center gap-6 text-sm text-muted-foreground">
          <Link href="/" className="hover:text-foreground transition-colors">
            Vue d&apos;ensemble
          </Link>
          <Link
            href="/pages"
            className="hover:text-foreground transition-colors"
          >
            Pages
          </Link>
          <Link
            href="/health"
            className="hover:text-foreground transition-colors"
          >
            Pipeline
          </Link>
        </div>
      </div>
    </nav>
  );
}
