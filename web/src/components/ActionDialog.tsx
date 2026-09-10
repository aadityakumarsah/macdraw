import {
  Brush,
  Layers,
  Plus,
  Shapes,
  Sparkles,
  Terminal,
  type LucideIcon,
} from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

const METADATA: Record<
  string,
  { title: string; body: string; action: string; icon: LucideIcon }
> = {
  blank: {
    title: "New blank file",
    body: "Open an empty canvas to start drawing and diagramming.",
    action: "Create file",
    icon: Plus,
  },
  ai: {
    title: "Generate an AI diagram",
    body: "Describe the diagram you want and Eraser AI will sketch it.",
    action: "Generate",
    icon: Sparkles,
  },
  mcp: {
    title: "Connect Eraser MCP",
    body: "Expose this workspace to an MCP server so agents can create files.",
    action: "Connect",
    icon: Terminal,
  },
  template: {
    title: "Create a template",
    body: "Turn the current canvas into a reusable template for the team.",
    action: "Save template",
    icon: Layers,
  },
  style: {
    title: "Create a custom style",
    body: "Pick colors and shapes that define how new diagrams should look.",
    action: "Open style studio",
    icon: Shapes,
  },
};

export function ActionDialog({ kind, onClose }: { kind: string | null; onClose: () => void }) {
  const meta = kind ? METADATA[kind] : undefined;
  const Icon = meta?.icon ?? Brush;
  return (
    <Dialog open={kind !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="border-border bg-popover sm:max-w-[400px]">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2.5 text-[15px] text-foreground">
            <Icon size={18} strokeWidth={1.6} className="text-secondary" />
            {meta?.title ?? ""}
          </DialogTitle>
          <DialogDescription className="text-[13px] leading-relaxed text-secondary">
            {meta?.body}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button
            onClick={onClose}
            className="h-[36px] rounded-[5px] bg-primary px-5 text-[13px] font-medium text-primary-foreground shadow-none hover:bg-primary-hover"
          >
            {meta?.action ?? "OK"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}