import {
  ChevronDown,
  CircleDot,
  ChevronLeft,
  Hand,
  History,
  Magnet,
  MoreHorizontal,
  MousePointer2,
  Redo2,
  Send,
  Square,
  StickyNote,
  Type,
  Undo2,
} from "lucide-react";
import type { Page } from "@/lib/types";
import { Button } from "@/components/ui/button";

export function Editor({
  page,
  onBack,
}: {
  page: Page;
  onBack: () => void;
}) {
  return (
    <div className="flex h-full flex-col">
      <div className="flex h-[48px] items-center gap-2 border-b border-border px-4">
        <button
          onClick={onBack}
          className="flex h-7 cursor-pointer items-center gap-1 rounded-[5px] px-2 text-[12.5px] text-secondary transition-colors hover:bg-foreground/5 hover:text-foreground"
        >
          <ChevronLeft size={14} />
          Files
        </button>
        <div className="mx-1 h-4 w-px bg-border" />
        <span className="text-[13.5px] font-medium text-foreground">{page.name}</span>
        <ChevronDown size={13} className="text-muted" />
        <div className="flex-1" />
        <button className="cursor-pointer rounded-[4px] p-1 text-secondary hover:bg-foreground/5">
          <MoreHorizontal size={16} />
        </button>
      </div>

      <div className="flex h-[44px] items-center gap-1 px-4">
        <Tool active icon={MousePointer2} label="Select" />
        <Tool icon={Hand} label="Pan" />
        <Tool icon={Square} label="Rectangle" />
        <Tool icon={CircleDot} label="Ellipse" />
        <Tool icon={Type} label="Text" />
        <Tool icon={StickyNote} label="Sticky note" />
        <div className="mx-2 h-4 w-px bg-border" />
        <button className="cursor-pointer rounded-[4px] p-1.5 text-secondary hover:bg-foreground/5">
          <Undo2 size={14} />
        </button>
        <button className="cursor-pointer rounded-[4px] p-1.5 text-secondary hover:bg-foreground/5">
          <Redo2 size={14} />
        </button>
        <button className="cursor-pointer rounded-[4px] p-1.5 text-secondary hover:bg-foreground/5">
          <History size={14} />
        </button>
        <div className="flex-1" />
        <button className="flex cursor-pointer items-center gap-1.5 rounded-[5px] px-2 py-1.5 text-[12px] text-secondary hover:bg-foreground/5">
          <Magnet size={14} />
          Snap
        </button>
        <Button className="ml-2 h-[30px] rounded-[5px] bg-primary px-3 text-[12.5px] font-medium text-primary-foreground shadow-none hover:bg-primary-hover">
          <Send size={13} />
          Share
        </Button>
      </div>

      <div className="relative flex flex-1 overflow-hidden bg-foreground/[0.035]">
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center gap-2">
          <p className="text-[13.5px] text-muted">Empty canvas</p>
          <p className="text-[12px] text-muted/70">
            Use the tools above to sketch, then share with your team.
          </p>
        </div>
      </div>
    </div>
  );
}

function Tool({
  icon: Icon,
  label,
  active = false,
}: {
  icon: typeof MousePointer2;
  label: string;
  active?: boolean;
}) {
  return (
    <button
      title={label}
      className={`flex h-8 w-8 cursor-pointer items-center justify-center rounded-[5px] transition-colors ${
        active ? "bg-active text-foreground" : "text-secondary hover:bg-foreground/5"
      }`}
    >
      <Icon size={16} strokeWidth={1.6} />
    </button>
  );
}