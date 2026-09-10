import { useState } from "react";
import {
  Archive,
  Blocks,
  Bot,
  Brush,
  ChevronDown,
  FolderPlus,
  Grid,
  Lock,
  Sparkles,
  type LucideIcon,
} from "lucide-react";
import { Logo } from "@/components/Logo";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "cn";
import { usePages } from "@/context/PagesContext";

export function Sidebar({ onNewFile, onOpenCard }: SidebarProps) {
  return (
    <aside className="relative flex h-screen w-[280px] shrink-0 flex-col border-r border-border bg-sidebar px-6 pb-4 pt-[46px]">
      <WorkspaceSelector />
      <PrimaryNavigation />
      <TeamFolders />
      <div className="flex-1" />
      <TrialCard />
      <UtilityNavigation />
      <div className="mt-5">
        <NewFileButton onNewFile={onNewFile} onOpenCard={onOpenCard} />
      </div>
    </aside>
  );
}

type SidebarProps = {
  onNewFile: () => void;
  onOpenCard: (kind: string) => void;
};

function WorkspaceSelector() {
  const { workspace } = usePages();
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex w-full cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-left transition-colors hover:bg-foreground/5">
          <Logo />
          <span className="text-[14.5px] font-medium tracking-[-0.01em] text-foreground">
            {workspace?.name ?? "Workspace"}
          </span>
          <ChevronDown size={15} strokeWidth={1.75} className="ml-auto text-muted" />
        </button>
      </PopoverTrigger>
      <PopoverContent
        align="start"
        sideOffset={8}
        className="w-[240px] border-border bg-popover p-1.5"
      >
        <div className="px-2 py-1.5 text-[11px] font-semibold uppercase tracking-wider text-muted">
          Workspaces
        </div>
        <button className="flex w-full items-center gap-2.5 rounded-md px-2 py-2 text-left hover:bg-foreground/5">
          <Logo />
          <span className="text-[13px] text-foreground">{workspace?.name ?? "Workspace"}</span>
        </button>
        <button className="flex w-full items-center gap-2.5 rounded-md px-2 py-2 text-left hover:bg-foreground/5">
          <span className="grid size-[24px] place-items-center rounded-[6px] border border-dashed border-border text-secondary">
            +
          </span>
          <span className="text-[13px] text-secondary">Create workspace</span>
        </button>
      </PopoverContent>
    </Popover>
  );
}

const NAV_ITEMS: {
  label: string;
  icon: LucideIcon;
  shortcut?: string;
  badge?: { label: string; tone: "blue" };
}[] = [
  { label: "All Files", icon: Grid, shortcut: "A" },
  { label: "Private Files", icon: Lock, badge: { label: "UPGRADE", tone: "blue" } },
  { label: "Archive", icon: Archive, shortcut: "E" },
];

function PrimaryNavigation() {
  const [active, setActive] = useState("All Files");
  return (
    <nav className="mt-[42px] space-y-1">
      {NAV_ITEMS.map((item) => {
        const Icon = item.icon;
        const isActive = active === item.label;
        return (
          <button
            key={item.label}
            onClick={() => setActive(item.label)}
            className={cn(
              "flex h-[38px] w-full items-center gap-2.5 rounded-[5px] border px-2.5 text-left text-[14px] font-medium transition-colors",
              isActive
                ? "border-border bg-active text-foreground"
                : "border-transparent text-secondary hover:bg-foreground/5",
            )}
          >
            <Icon size={16} strokeWidth={1.6} className={isActive ? "text-foreground" : "text-secondary"} />
            <span className="flex-1">{item.label}</span>
            {item.badge && (
              <span className="rounded-full bg-primary/15 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-primary/90">
                {item.badge.label}
              </span>
            )}
            {item.shortcut && (
              <kbd className="rounded-[3px] border border-border bg-foreground/10 px-1 text-[10px] font-medium text-muted">
                {item.shortcut}
              </kbd>
            )}
          </button>
        );
      })}
    </nav>
  );
}

function TeamFolders() {
  return (
    <div className="mt-9">
      <div className="flex items-center justify-between px-1">
        <span className="text-[10.5px] font-semibold uppercase tracking-[0.14em] text-muted">
          Team Folders
        </span>
        <button className="cursor-pointer rounded hover:bg-foreground/5" aria-label="New folder">
          <FolderPlus size={14} strokeWidth={1.6} className="text-muted" />
        </button>
      </div>
    </div>
  );
}

function TrialCard() {
  return (
    <div className="mx-auto w-full max-w-[240px] rounded-[9px] border border-border bg-popover p-4">
      <p className="text-[13px] font-semibold text-foreground">Fraser Free Trial</p>
      <div className="mt-3 h-[5px] w-full overflow-hidden rounded-full bg-border">
        <div className="h-full w-1/3 rounded-full bg-secondary" />
      </div>
      <p className="mt-2 text-[12px] text-secondary">1 of 3 files.</p>
      <p className="mt-2 text-[11.5px] leading-[1.55] text-muted">
        Upgrade your plan for unlimited files &amp; more features
      </p>
      <Button
        size="lg"
        className="mt-4 h-[40px] w-full rounded-[5px] bg-primary text-[14px] font-medium text-primary-foreground shadow-none hover:bg-primary-hover"
      >
        Upgrade
      </Button>
    </div>
  );
}

const UTILITY_LINKS: {
  label: string;
  icon: LucideIcon;
  shortcut?: string;
  badge?: string;
}[] = [
  { label: "AI Presets", icon: Sparkles, shortcut: "T" },
  { label: "Custom Styles", icon: Brush, shortcut: "S" },
  { label: "MCP", icon: Blocks, shortcut: "C" },
  { label: "Eraserbot", icon: Bot, badge: "BETA" },
];

function UtilityNavigation() {
  return (
    <div className="mt-4 space-y-0.5">
      {UTILITY_LINKS.map((item) => {
        const Icon = item.icon;
        return (
          <button
            key={item.label}
            className="flex h-[30px] w-full items-center gap-2.5 rounded-[5px] px-2.5 text-left text-[13px] font-medium text-secondary transition-colors hover:bg-foreground/5 hover:text-foreground"
          >
            <Icon size={15} strokeWidth={1.6} className="text-muted" />
            <span className="flex-1">{item.label}</span>
            {item.badge && (
              <span className="rounded-[5px] bg-primary/20 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-primary/90">
                {item.badge}
              </span>
            )}
            {item.shortcut && (
              <kbd className="rounded-[3px] text-[10.5px] font-medium text-muted">
                {item.shortcut}
              </kbd>
            )}
          </button>
        );
      })}
    </div>
  );
}

function NewFileButton({ onNewFile, onOpenCard }: { onNewFile: () => void; onOpenCard: (k: string) => void }) {
  const items = [
    { key: "blank", label: "Blank file" },
    { key: "ai", label: "AI diagram" },
    { key: "template", label: "From template" },
    { key: "style", label: "With a custom style" },
  ];
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          className="h-[55px] w-full justify-between rounded-[6px] bg-primary px-4 text-[15px] font-semibold text-primary-foreground shadow-none hover:bg-primary-hover"
          onClick={onNewFile}
        >
          <span>New File</span>
          <span className="flex items-center gap-3">
            <kbd className="text-[12px] font-medium text-primary-foreground/80">⌃ N</kbd>
            <ChevronDown size={16} strokeWidth={2} />
          </span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        side="top"
        align="start"
        sideOffset={8}
        className="w-[200px] border-border bg-popover p-1"
      >
        {items.map((item, i) => (
          <div key={item.key}>
            {i > 0 && <DropdownMenuSeparator className="my-1 bg-border" />}
            <DropdownMenuItem
              className="cursor-pointer px-2 py-1.5 text-[13px] text-foreground focus:bg-foreground/5"
              onClick={() => onOpenCard(item.key)}
            >
              {item.label}
            </DropdownMenuItem>
          </div>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}