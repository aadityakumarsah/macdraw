import { Layers, Plus, Shapes, Sparkles, Terminal, type LucideIcon } from "lucide-react";

type CardDef = { key: string; label: string; icon: LucideIcon };

const CARDS: CardDef[] = [
  { key: "blank", label: "Create a Blank File", icon: Plus },
  { key: "ai", label: "Generate an AI Diagram", icon: Sparkles },
  { key: "mcp", label: "Connect Eraser MCP", icon: Terminal },
  { key: "template", label: "Create a Template", icon: Layers },
  { key: "style", label: "Create a Custom Style", icon: Shapes },
];

export function ActionCards({ onOpenCard }: { onOpenCard: (kind: string) => void }) {
  return (
    <div className="mt-9 grid grid-cols-2 gap-6 sm:grid-cols-3 lg:grid-cols-5">
      {CARDS.map((card) => {
        const Icon = card.icon;
        return (
          <button
            key={card.key}
            onClick={() => onOpenCard(card.key)}
            className="group flex h-[125px] cursor-pointer flex-col items-center justify-center gap-3 rounded-[6px] border border-border bg-card transition-colors hover:border-active hover:bg-active"
          >
            <Icon
              size={34}
              strokeWidth={1.5}
              className="text-secondary transition-colors group-hover:text-foreground"
            />
            <span className="px-3 text-center text-[15px] font-medium text-secondary group-hover:text-foreground">
              {card.label}
            </span>
          </button>
        );
      })}
    </div>
  );
}