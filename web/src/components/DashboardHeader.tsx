import { useState } from "react";
import { Moon, Search, Send, Sun } from "lucide-react";
import { TABS, type Tab } from "@/lib/data";
import { cn } from "cn";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { usePages } from "@/context/PagesContext";
import { useTheme } from "@/lib/theme";
import { initials } from "@/lib/format";
import { supabase } from "@/lib/supabase";

export function DashboardHeader({
  tab,
  onTabChange,
  query,
  onQueryChange,
}: {
  tab: Tab;
  onTabChange: (t: Tab) => void;
  query: string;
  onQueryChange: (q: string) => void;
}) {
  const [inviteOpen, setInviteOpen] = useState(false);
  const [email, setEmail] = useState("");
  const { user, workspace, status, error } = usePages();
  const { theme, toggle } = useTheme();

  return (
    <>
      <header className="flex items-center justify-between gap-6">
        <div className="flex items-center gap-[38px]">
          {TABS.map((t) => {
            const active = tab === t.id;
            return (
              <button
                key={t.id}
                onClick={() => onTabChange(t.id)}
                className={cn(
                  "h-[30px] cursor-pointer rounded-[5px] text-[13.5px] font-medium transition-colors",
                  active
                    ? "border border-border bg-active px-4 text-foreground"
                    : "border border-transparent px-1 text-secondary hover:text-foreground",
                )}
              >
                {t.label}
              </button>
            );
          })}
        </div>

        <div className="flex items-center gap-3">
          <div className="relative">
            <Search
              size={15}
              strokeWidth={1.7}
              className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted"
            />
            <Input
              value={query}
              onChange={(e) => onQueryChange(e.target.value)}
              placeholder="Search"
              className="h-[32px] w-[210px] rounded-[5px] border-border bg-surface pl-8 pr-8 text-[13px] shadow-none placeholder:text-muted focus-visible:ring-ring/60"
            />
            <kbd className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 rounded-[3px] border border-border bg-black/25 px-1 text-[10px] font-medium text-muted">
              /
            </kbd>
          </div>

          <button className="flex h-[32px] cursor-pointer items-center rounded-[5px] border border-border bg-surface px-2.5 text-[11px] font-medium text-secondary hover:bg-active">
            ⌘K
          </button>

          <ConnectionBadge status={status} error={error} />

          <div className="flex items-center pl-1">
            <Avatar className="size-[26px] bg-border text-[10px] font-semibold text-secondary ring-2 ring-background">
              <AvatarFallback>
                {initials(user?.email)}
              </AvatarFallback>
            </Avatar>
            <div className="-ml-2 flex size-[24px] items-center justify-center rounded-full bg-active text-[9px] font-semibold text-secondary ring-2 ring-background">
              RB
            </div>
            <div className="-ml-2 flex size-[24px] items-center justify-center rounded-full bg-primary/40 text-[9px] font-semibold text-secondary ring-2 ring-background">
              JT
            </div>
          </div>

          <Button
            onClick={() => toggle()}
            variant="ghost"
            className="h-[32px] w-[32px] rounded-[5px] px-0 text-secondary hover:bg-active hover:text-foreground"
            title={`Switch to ${theme === "dark" ? "light" : "dark"} mode`}
          >
            {theme === "dark" ? <Sun size={15} strokeWidth={1.7} /> : <Moon size={15} strokeWidth={1.7} />}
          </Button>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button className="flex h-[32px] cursor-pointer items-center rounded-[5px] border border-border bg-surface px-2 text-[11.5px] font-medium text-secondary hover:bg-active hover:text-foreground">
                {workspace?.name ?? "…"}
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="min-w-[220px]">
              <DropdownMenuLabel className="text-[12px] font-medium text-muted-foreground">
                {user?.email}
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                className="text-[13px]"
                onSelect={() => supabase.auth.signOut()}
              >
                Sign out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>

          <Button
            onClick={() => setInviteOpen(true)}
            className="h-[32px] w-[80px] rounded-[5px] bg-primary text-[13px] font-medium text-primary-foreground shadow-none hover:bg-primary-hover"
          >
            <Send size={14} strokeWidth={1.8} />
            Invite
          </Button>
        </div>
      </header>

      <InviteDialog
        open={inviteOpen}
        onOpenChange={setInviteOpen}
        email={email}
        onEmail={setEmail}
      />
    </>
  );
}

function ConnectionBadge({ status, error }: { status: string; error: string | null }) {
  const fail = status === "closed" || status === "reconnecting" || !!error;
  return (
    <span
      title={fail ? "Reconnecting to MacDraw sync" : "Live sync connected"}
      className={cn(
        "flex items-center gap-1.5 rounded-full border border-border bg-surface px-2.5 py-1 text-[10.5px] font-medium",
        fail ? "text-destructive" : "text-secondary",
      )}
    >
      <span
        className={cn(
          "size-[6px] rounded-full",
          fail ? "animate-pulse bg-amber-400" : "bg-emerald-400",
        )}
      />
      {fail ? "reconnecting" : "live"}
    </span>
  );
}

function InviteDialog({
  open,
  onOpenChange,
  email,
  onEmail,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  email: string;
  onEmail: (e: string) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="border-border bg-popover sm:max-w-[400px]">
        <DialogHeader>
          <DialogTitle className="text-[15px] text-foreground">Invite to your workspace</DialogTitle>
          <DialogDescription className="text-[13px] text-secondary">
            Send an invite link so teammates can collaborate on files.
          </DialogDescription>
        </DialogHeader>
        <Input
          autoFocus
          value={email}
          onChange={(e) => onEmail(e.target.value)}
          placeholder="email@example.com"
          className="h-[36px] rounded-[5px] border-border bg-background text-[13px] shadow-none"
        />
        <DialogFooter>
          <Button
            onClick={() => onOpenChange(false)}
            className="h-[36px] rounded-[5px] bg-primary px-5 text-[13px] font-medium text-primary-foreground shadow-none hover:bg-primary-hover"
          >
            Send invite
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}