import { useState } from "react";
import { ArrowDownUp, MoreHorizontal } from "lucide-react";
import type { Page } from "@/lib/types";
import { timeAgo, initials } from "@/lib/format";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { usePages } from "@/context/PagesContext";

const GRID =
  "grid grid-cols-[1.5fr_0.9fr_0.9fr_0.9fr_0.7fr_0.7fr_28px] items-center gap-4 px-3";

export function FileTable({
  pages,
  onOpenFile,
}: {
  pages: Page[];
  onOpenFile: (p: Page) => void;
}) {
  const { user } = usePages();
  return (
    <div className="mt-14">
      <div className={GRID}>
        <Column>Name</Column>
        <Column>Location</Column>
        <Column>Created</Column>
        <Column className="flex items-center gap-1">
          Edited
          <ArrowDownUp size={11} strokeWidth={1.8} className="text-muted" />
        </Column>
        <Column>Comments</Column>
        <Column>Author</Column>
        <div />
      </div>

      <div className="mt-2 space-y-1.5">
        {pages.map((page) => (
          <FileRow key={page.id} page={page} onOpenFile={onOpenFile} />
        ))}
        {pages.length === 0 && (
          <div className="rounded-[6px] border border-border bg-surface px-3 py-8 text-center text-[13px] text-muted">
            No files here yet.
          </div>
        )}
      </div>
    </div>
  );
}

function Column({ children, className = "" }: { children?: React.ReactNode; className?: string }) {
  return (
    <div
      className={`text-[10.5px] font-semibold uppercase tracking-[0.1em] text-muted ${className}`}
    >
      {children}
    </div>
  );
}

function FileRow({
  page,
  onOpenFile,
}: {
  page: Page;
  onOpenFile: (p: Page) => void;
}) {
  const { user } = usePages();
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => onOpenFile(page)}
      onKeyDown={(e) => e.key === "Enter" && onOpenFile(page)}
      className={`${GRID} h-[56px] cursor-pointer rounded-[6px] border border-border bg-surface text-[13.5px] transition-colors hover:bg-card`}
    >
      <span className="truncate font-medium text-foreground">{page.name}</span>
      <span className="truncate text-secondary">In Shared</span>
      <span className="truncate text-secondary">{timeAgo(page.createdAt)}</span>
      <span className="truncate text-secondary">{timeAgo(page.updatedAt)}</span>
      <span className="truncate text-secondary">0</span>
      <Avatar initials={initials(user?.email)} />
      <div
        onClick={(e) => e.stopPropagation()}
        className="flex h-6 w-7 items-center justify-center"
      >
        <RowMenu page={page} />
      </div>
    </div>
  );
}

function Avatar({ initials }: { initials: string }) {
  return (
    <div className="flex size-[22px] items-center justify-center rounded-full bg-border text-[9px] font-semibold text-secondary">
      {initials}
    </div>
  );
}

function RowMenu({ page }: { page: Page }) {
  const { renamePage, duplicatePage, archivePage } = usePages();
  const [renaming, setRenaming] = useState(false);
  const [name, setName] = useState(page.name);
  const [confirmArchive, setConfirmArchive] = useState(false);

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            aria-label="File menu"
            className="grid h-6 w-7 cursor-pointer place-items-center rounded-[4px] text-secondary transition-colors hover:bg-foreground/5 hover:text-foreground"
          >
            <MoreHorizontal size={16} strokeWidth={1.7} />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          side="bottom"
          align="end"
          sideOffset={6}
          className="w-[170px] border-border bg-popover p-1"
        >
          <DropdownMenuItem
            className="cursor-pointer px-2 py-1.5 text-[13px] text-foreground focus:bg-foreground/5"
            onSelect={() => setRenaming(true)}
          >
            Rename
          </DropdownMenuItem>
          <DropdownMenuItem
            className="cursor-pointer px-2 py-1.5 text-[13px] text-foreground focus:bg-foreground/5"
            onSelect={() => duplicatePage(page.id)}
          >
            Duplicate
          </DropdownMenuItem>
          <DropdownMenuItem
            className="cursor-pointer px-2 py-1.5 text-[13px] text-foreground focus:bg-foreground/5"
            onSelect={() => setConfirmArchive(true)}
          >
            Archive
          </DropdownMenuItem>
          <DropdownMenuSeparator className="my-1 bg-border" />
          <DropdownMenuItem
            className="cursor-pointer px-2 py-1.5 text-[13px] text-destructive focus:bg-foreground/5 focus:text-destructive"
            onSelect={() => setConfirmArchive(true)}
          >
            Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={renaming} onOpenChange={setRenaming}>
        <DialogContent className="border-border bg-popover sm:max-w-[360px]">
          <DialogHeader>
            <DialogTitle className="text-[14px] text-foreground">Rename file</DialogTitle>
          </DialogHeader>
          <Input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                renamePage(page.id, name);
                setRenaming(false);
              }
            }}
            className="h-[36px] rounded-[5px] border-border bg-background text-[13px] shadow-none"
          />
          <DialogFooter>
            <Button
              onClick={() => {
                renamePage(page.id, name);
                setRenaming(false);
              }}
              className="h-[36px] rounded-[5px] bg-primary px-5 text-[13px] font-medium text-primary-foreground shadow-none hover:bg-primary-hover"
            >
              Rename
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmArchive} onOpenChange={setConfirmArchive}>
        <DialogContent className="border-border bg-popover sm:max-w-[360px]">
          <DialogHeader>
            <DialogTitle className="text-[14px] text-foreground">
              Delete "{page.name}"?
            </DialogTitle>
          </DialogHeader>
          <p className="text-[12.5px] text-secondary">
            This moves the file to Archive. You can restore it later from the Archive tab.
          </p>
          <DialogFooter>
            <Button
              onClick={() => setConfirmArchive(false)}
              variant="outline"
              className="h-[36px] rounded-[5px] border-border bg-surface px-5 text-[13px] text-foreground shadow-none hover:bg-active"
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                archivePage(page.id);
                setConfirmArchive(false);
              }}
              className="h-[36px] rounded-[5px] bg-destructive px-5 text-[13px] font-medium text-white shadow-none hover:bg-destructive/90"
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}