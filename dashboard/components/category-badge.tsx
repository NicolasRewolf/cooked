import { cn } from "@/lib/utils";
import { CATEGORY_LABEL, categorize, type PageCategory } from "@/lib/page-category";

const styles: Record<PageCategory, string> = {
  home: "bg-foreground/8 text-foreground ring-1 ring-inset ring-foreground/10",
  cabinet:
    "bg-info/10 text-info ring-1 ring-inset ring-info/15",
  expertise:
    "bg-accent-base/10 text-foreground ring-1 ring-inset ring-foreground/15",
  article:
    "bg-surface-subtle text-muted-foreground ring-1 ring-inset ring-border",
};

export function CategoryBadge({
  path,
  className,
}: {
  path: string;
  className?: string;
}) {
  const cat = categorize(path);
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-md px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-wide",
        styles[cat],
        className
      )}
    >
      {CATEGORY_LABEL[cat]}
    </span>
  );
}
