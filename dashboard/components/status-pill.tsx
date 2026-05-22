import { cn } from "@/lib/utils";

type Status = "healthy" | "degraded" | "critical";

const styles: Record<Status, string> = {
  healthy:
    "bg-success/10 text-success ring-1 ring-inset ring-success/20",
  degraded:
    "bg-warning/10 text-warning ring-1 ring-inset ring-warning/20",
  critical:
    "bg-danger/10 text-danger ring-1 ring-inset ring-danger/20",
};

const labels: Record<Status, string> = {
  healthy: "OK",
  degraded: "dégradé",
  critical: "critique",
};

export function StatusPill({
  status,
  className,
}: {
  status: Status;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 font-mono text-xs uppercase tracking-wide",
        styles[status],
        className
      )}
    >
      <span
        className={cn(
          "h-1.5 w-1.5 rounded-full",
          status === "healthy" && "bg-success",
          status === "degraded" && "bg-warning",
          status === "critical" && "bg-danger"
        )}
      />
      {labels[status]}
    </span>
  );
}
