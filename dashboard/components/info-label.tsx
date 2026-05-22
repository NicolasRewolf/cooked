import { Info } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

/**
 * Label avec icône ℹ️ et tooltip explicatif. À utiliser dans les headers
 * de colonnes et autres labels techniques où le terme n'est pas évident
 * pour un non-SEO (ex : Plouton, Lucie).
 *
 * Note : le trigger Base UI rend un <button> par défaut. On le restyle
 * en inline-flex pour qu'il s'intègre dans un <th>.
 */
export function InfoLabel({
  label,
  hint,
  className,
}: {
  label: string;
  hint: string;
  className?: string;
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        className={cn(
          "inline-flex items-center gap-1 cursor-help bg-transparent p-0 font-inherit text-inherit",
          className
        )}
      >
        {label}
        <Info className="h-3 w-3 opacity-50" aria-hidden="true" />
      </TooltipTrigger>
      <TooltipContent
        side="top"
        className="max-w-xs text-left text-xs leading-relaxed"
      >
        {hint}
      </TooltipContent>
    </Tooltip>
  );
}
